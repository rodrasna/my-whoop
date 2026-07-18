import Foundation
import WhoopProtocol

/// Anchor used to re-map type-47 absolute RTC timestamps when the strap clock is lost
/// (future / absurd unix) but kept ticking with an approximately constant offset.
///
/// Heuristic: at detection, DATA_RANGE reports `strapNewestCorrupt`. We treat that marker
/// as "approximately now" (`wallAtDetect`) and subtract
/// `Δ = strapNewestCorrupt − wallAtDetect` from every corrupt sample.
///
/// This cannot invent hours the strap never recorded. It only recovers samples that were
/// written under a wrong RTC base.
struct ClockLossAnchor: Equatable {
    let wallAtDetect: Int
    let strapNewestCorrupt: Int
    let strapOldestCorrupt: Int?
    /// Last sane historical HR frontier before the loss (optional guardrail).
    let lastGoodFrontier: Int?

    var deltaSeconds: Int { strapNewestCorrupt - wallAtDetect }

    /// Correct one absolute RTC unix. Returns nil when the result is still not wall-sane
    /// or lands unreasonably before the last known-good frontier.
    func correct(_ ts: Int, wallNow: Int? = nil) -> Int? {
        let wall = wallNow ?? wallAtDetect
        guard !ClockPolicy.isSaneWallRelative(ts, wallNow: wall) else { return ts }
        let corrected = ts - deltaSeconds
        guard ClockPolicy.isSaneWallRelative(corrected, wallNow: wall) else { return nil }
        if let good = lastGoodFrontier, corrected + 3_600 < good {
            // More than 1h before the last good frontier → likely garbage, not this episode.
            return nil
        }
        return corrected
    }
}

/// Pure helpers for detecting corrupt historical timestamps and remapping Streams.
enum ClockLossPolicy {
    /// True when a decoded sample ts looks like CLOCK-LOST flash (future or absurd past).
    static func needsCorrection(_ ts: Int, wallNow: Int) -> Bool {
        !ClockPolicy.isSaneWallRelative(ts, wallNow: wallNow)
    }

    /// Drop rows whose timestamps are not wall-sane (no remap). Used when no CLOCK-LOST
    /// anchor is active so we never persist 2029 into SQLite.
    static func dropInsaneTimestamps(_ streams: Streams, wallNow: Int) -> (streams: Streams, dropped: Int) {
        var dropped = 0
        func keep(_ ts: Int) -> Int? {
            if ClockPolicy.isSaneWallRelative(ts, wallNow: wallNow) { return ts }
            dropped += 1
            return nil
        }
        let out = Streams(
            hr: streams.hr.compactMap { s in keep(s.ts).map { HRSample(ts: $0, bpm: s.bpm) } },
            rr: streams.rr.compactMap { s in keep(s.ts).map { RRInterval(ts: $0, rrMs: s.rrMs) } },
            spo2: streams.spo2.compactMap { s in keep(s.ts).map { SpO2Sample(ts: $0, red: s.red, ir: s.ir, unit: s.unit) } },
            skinTemp: streams.skinTemp.compactMap { s in keep(s.ts).map { SkinTempSample(ts: $0, raw: s.raw, unit: s.unit) } },
            resp: streams.resp.compactMap { s in keep(s.ts).map { RespSample(ts: $0, raw: s.raw, unit: s.unit) } },
            gravity: streams.gravity.compactMap { s in keep(s.ts).map { GravitySample(ts: $0, x: s.x, y: s.y, z: s.z, unit: s.unit) } },
            events: streams.events.compactMap { s in keep(s.ts).map { WhoopEvent(ts: $0, kind: s.kind, payload: s.payload) } },
            battery: streams.battery.compactMap { s in keep(s.ts).map { BatterySample(ts: $0, soc: s.soc, mv: s.mv, charging: s.charging) } }
        )
        return (out, dropped)
    }

    /// Apply `anchor` to every stream row. Rows that cannot be corrected are dropped
    /// (better than inserting 2029 into SQLite / server).
    static func remapStreams(_ streams: Streams, anchor: ClockLossAnchor, wallNow: Int) -> (streams: Streams, remapped: Int, dropped: Int) {
        var remapped = 0
        var dropped = 0

        func mapTs(_ ts: Int) -> Int? {
            if ClockPolicy.isSaneWallRelative(ts, wallNow: wallNow) { return ts }
            if let c = anchor.correct(ts, wallNow: wallNow) {
                remapped += 1
                return c
            }
            dropped += 1
            return nil
        }

        let hr = streams.hr.compactMap { s -> HRSample? in
            guard let ts = mapTs(s.ts) else { return nil }
            return HRSample(ts: ts, bpm: s.bpm)
        }
        let rr = streams.rr.compactMap { s -> RRInterval? in
            guard let ts = mapTs(s.ts) else { return nil }
            return RRInterval(ts: ts, rrMs: s.rrMs)
        }
        let spo2 = streams.spo2.compactMap { s -> SpO2Sample? in
            guard let ts = mapTs(s.ts) else { return nil }
            return SpO2Sample(ts: ts, red: s.red, ir: s.ir, unit: s.unit)
        }
        let skin = streams.skinTemp.compactMap { s -> SkinTempSample? in
            guard let ts = mapTs(s.ts) else { return nil }
            return SkinTempSample(ts: ts, raw: s.raw, unit: s.unit)
        }
        let resp = streams.resp.compactMap { s -> RespSample? in
            guard let ts = mapTs(s.ts) else { return nil }
            return RespSample(ts: ts, raw: s.raw, unit: s.unit)
        }
        let gravity = streams.gravity.compactMap { s -> GravitySample? in
            guard let ts = mapTs(s.ts) else { return nil }
            return GravitySample(ts: ts, x: s.x, y: s.y, z: s.z, unit: s.unit)
        }
        let events = streams.events.compactMap { s -> WhoopEvent? in
            guard let ts = mapTs(s.ts) else { return nil }
            return WhoopEvent(ts: ts, kind: s.kind, payload: s.payload)
        }
        let battery = streams.battery.compactMap { s -> BatterySample? in
            guard let ts = mapTs(s.ts) else { return nil }
            return BatterySample(ts: ts, soc: s.soc, mv: s.mv, charging: s.charging)
        }

        return (Streams(hr: hr, rr: rr, spo2: spo2, skinTemp: skin, resp: resp,
                        gravity: gravity, events: events, battery: battery),
                remapped, dropped)
    }

    /// Build an anchor from a future DATA_RANGE reading.
    static func anchor(strapNewest: Int, strapOldest: Int?, wallAtDetect: Int, lastGoodFrontier: Int?) -> ClockLossAnchor {
        ClockLossAnchor(wallAtDetect: wallAtDetect,
                        strapNewestCorrupt: strapNewest,
                        strapOldestCorrupt: strapOldest,
                        lastGoodFrontier: lastGoodFrontier)
    }
}
