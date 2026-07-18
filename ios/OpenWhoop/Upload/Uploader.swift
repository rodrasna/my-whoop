import Foundation
import WhoopProtocol
import WhoopStore

// MARK: - Uploader

/// Drains both decoded streams and raw batch outbox to the server.
/// Idempotent and retry-safe: rows / batches are marked synced ONLY on HTTP 2xx.
/// Non-2xx or thrown errors leave state unchanged for retry.
///
/// Decoded streams drain by a per-row `synced` flag (NOT a forward-only highwater): each drain
/// reads a page of `synced = 0` rows oldest-ts-first, POSTs them, and marks EXACTLY those rows
/// synced on 2xx. This correctly uploads backfilled (older-ts) rows the historical offload inserts
/// after a recent live row already advanced past them — the old highwater stranded those forever.
final class Uploader {
    /// Page size for most decoded streams.
    private static let pageLimit = 5000
    /// Smaller HR pages — large HR POSTs were timing out while events/battery still uploaded.
    private static let hrPageLimit = 1200

    private struct IngestResult {
        let ok: Bool
        let skippedForKey: Int
    }

    private let config: UploaderConfig
    private let store: WhoopStore
    private let deviceId: String
    private let session: URLSession

    init(config: UploaderConfig,
         store: WhoopStore,
         deviceId: String,
         session: URLSession = .shared) {
        self.config = config
        self.store = store
        self.deviceId = deviceId
        self.session = session
    }

    /// Drain all pending decoded streams.
    ///
    /// Raw upload is NO LONGER part of the default drain path: the app is decoded-only by
    /// default (raw capture is OFF unless the research toggle is enabled). `drainRaw()` and the
    /// `/v1/ingest` raw path remain available below for an explicit, future research export, but
    /// they MUST NOT run automatically here.
    func drain() async {
        await drainDecoded()
    }

    // MARK: - Decoded drain

    private func drainDecoded() async {
        // Each stream is a separate POST and drains by its own `synced = 0` page.
        await drainHR()
        await drainRR()
        await drainEvents()
        await drainBattery()
        // Type-47 V24 biometric streams (raw ADC; cloud computes human units).
        // Gravity before spo2/skin/resp: sleep detection on the server requires motion;
        // deferring it behind large skin/resp backlogs left nights without sleep for hours.
        await drainGravity()
        await drainSpo2()
        await drainSkinTemp()
        await drainResp()
    }

    /// Generic decoded drain: page `synced = 0` rows (oldest ts first), POST each page, and mark
    /// EXACTLY the uploaded rows synced on 2xx. Stops on the first non-2xx / failure (rows stay
    /// `synced = 0` → retried next connect). Uploads backfilled/out-of-order rows correctly because
    /// selection is by the per-row flag, not a ts cursor. Idempotent: re-presenting a synced row to
    /// the server is harmless (server upserts by natural key).
    ///
    /// `read` returns one page (already ordered ts ASC, `synced = 0`, capped at `limit`).
    /// `bodyKey` + `encode` build the JSON body for that stream. `mark` flips the page synced.
    private func drainStream<Row>(
        read: (_ limit: Int) async throws -> [Row],
        pageLimit: Int = pageLimit,
        bodyKey: String,
        encode: (Row) -> [String: Any],
        mark: ([Row]) async throws -> Void
    ) async {
        while true {
            guard let rows = try? await read(pageLimit), !rows.isEmpty else { return }
            let streamsBody: [String: Any] = [bodyKey: rows.map(encode)]
            let result = await postDecoded(streams: streamsBody, streamKey: bodyKey)
            if result.ok {
                if result.skippedForKey < rows.count {
                    try? await mark(rows)
                } else {
                    print("Uploader: server skipped all \(rows.count) \(bodyKey) rows — leaving synced=0 for retry")
                    return
                }
            } else {
                print("Uploader: POST /v1/ingest-decoded failed for \(bodyKey) (\(rows.count) rows)")
                return
            }
            if rows.count < pageLimit { return }
        }
    }

    private func drainHR() async {
        await drainStream(
            read: { try await self.store.unsyncedHR(deviceId: self.deviceId, limit: $0) },
            pageLimit: Self.hrPageLimit,
            bodyKey: "hr",
            encode: { ["ts": $0.ts, "bpm": $0.bpm] },
            mark: { try await self.store.markHRSynced(deviceId: self.deviceId, rows: $0) })
    }

    private func drainRR() async {
        await drainStream(
            read: { try await self.store.unsyncedRR(deviceId: self.deviceId, limit: $0) },
            bodyKey: "rr",
            encode: { ["ts": $0.ts, "rr_ms": $0.rrMs] },
            mark: { try await self.store.markRRSynced(deviceId: self.deviceId, rows: $0) })
    }

    private func drainEvents() async {
        await drainStream(
            read: { try await self.store.unsyncedEvents(deviceId: self.deviceId, limit: $0) },
            bodyKey: "events",
            encode: { ev -> [String: Any] in
                var d: [String: Any] = ["ts": ev.ts, "kind": ev.kind]
                if let payloadData = try? JSONEncoder().encode(ev.payload),
                   let payloadObj = try? JSONSerialization.jsonObject(with: payloadData) {
                    d["payload"] = payloadObj
                }
                return d
            },
            mark: { try await self.store.markEventsSynced(deviceId: self.deviceId, rows: $0) })
    }

    private func drainBattery() async {
        await drainStream(
            read: { try await self.store.unsyncedBattery(deviceId: self.deviceId, limit: $0) },
            bodyKey: "battery",
            encode: { b -> [String: Any] in
                var d: [String: Any] = ["ts": b.ts]
                if let soc = b.soc { d["soc"] = soc }
                if let mv = b.mv { d["mv"] = mv }
                if let charging = b.charging { d["charging"] = charging }
                return d
            },
            mark: { try await self.store.markBatterySynced(deviceId: self.deviceId, rows: $0) })
    }

    private func drainSpo2() async {
        await drainStream(
            read: { try await self.store.unsyncedSpo2(deviceId: self.deviceId, limit: $0) },
            bodyKey: "spo2",
            encode: { ["ts": $0.ts, "red": $0.red, "ir": $0.ir] },
            mark: { try await self.store.markSpo2Synced(deviceId: self.deviceId, rows: $0) })
    }

    private func drainSkinTemp() async {
        await drainStream(
            read: { try await self.store.unsyncedSkinTemp(deviceId: self.deviceId, limit: $0) },
            bodyKey: "skin_temp",
            encode: { ["ts": $0.ts, "raw": $0.raw] },
            mark: { try await self.store.markSkinTempSynced(deviceId: self.deviceId, rows: $0) })
    }

    private func drainResp() async {
        await drainStream(
            read: { try await self.store.unsyncedResp(deviceId: self.deviceId, limit: $0) },
            bodyKey: "resp",
            encode: { ["ts": $0.ts, "raw": $0.raw] },
            mark: { try await self.store.markRespSynced(deviceId: self.deviceId, rows: $0) })
    }

    private func drainGravity() async {
        await drainStream(
            read: { try await self.store.unsyncedGravity(deviceId: self.deviceId, limit: $0) },
            bodyKey: "gravity",
            encode: { ["ts": $0.ts, "x": $0.x, "y": $0.y, "z": $0.z] },
            mark: { try await self.store.markGravitySynced(deviceId: self.deviceId, rows: $0) })
    }

    /// POST to /v1/ingest-decoded.
    private func postDecoded(streams: [String: Any], streamKey: String) async -> IngestResult {
        let body: [String: Any] = [
            "device": ["id": deviceId],
            "streams": streams
        ]
        return await postIngestDecoded(body: body, streamKey: streamKey)
    }

    private func postIngestDecoded(body: [String: Any], streamKey: String) async -> IngestResult {
        guard let url = URL(string: "/v1/ingest-decoded", relativeTo: config.baseURL)
                     ?? URL(string: config.baseURL.absoluteString + "/v1/ingest-decoded") else {
            return IngestResult(ok: false, skippedForKey: 0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return IngestResult(ok: false, skippedForKey: 0)
        }
        request.httpBody = data
        do {
            let (respData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return IngestResult(ok: false, skippedForKey: 0)
            }
            let skipped = Self.skippedCount(in: respData, streamKey: streamKey)
            return IngestResult(ok: true, skippedForKey: skipped)
        } catch {
            return IngestResult(ok: false, skippedForKey: 0)
        }
    }

    private static func skippedCount(in data: Data, streamKey: String) -> Int {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let skipped = obj["skipped"] as? [String: Any] else { return 0 }
        return (skipped[streamKey] as? NSNumber)?.intValue ?? 0
    }

    // MARK: - Raw drain (explicit research export only)

    /// Drain the ENTIRE raw outbox (pages until empty), so a backfill backlog clears in one
    /// connected session rather than ~one page per connect. Stops on the first server/network
    /// failure (the batch stays pending → retried next connect). An unreadable batch is skipped
    /// but tracked so paging can't spin on it.
    ///
    /// NOTE: This is intentionally NOT called from `drain()`. Raw capture is OFF by default and
    /// this path exists only for a future, explicit research export. Decoded streams are the
    /// product of record; raw is never auto-uploaded.
    func drainRaw() async {
        var attempted = Set<String>()
        while true {
            guard let pending = try? await store.pendingRawBatches(limit: 50) else { return }
            let fresh = pending.filter { !attempted.contains($0.batchId) }
            if fresh.isEmpty { return }   // nothing new to do this drain
            for meta in fresh {
                attempted.insert(meta.batchId)
                guard let frames = try? await store.rawFrames(batchId: meta.batchId) else { continue }
                let body: [String: Any] = [
                    "batch_id": meta.batchId,
                    "device": ["device_id": meta.deviceId],
                    "clock_ref": [
                        "device": meta.clockRef.device,
                        "wall": meta.clockRef.wall
                    ],
                    "decode_streams": false,
                    "frames": frames.map { ["hex": $0.hexString] }
                ]
                let now = Int(Date().timeIntervalSince1970)
                if await post(path: "/v1/ingest", body: body) {
                    try? await store.markRawBatchSynced(batchId: meta.batchId, at: now)
                } else {
                    return   // server/network failure → stop; retry on next connect
                }
            }
        }
    }

    // MARK: - HTTP helper

    /// Perform a POST with JSON body. Returns true on 2xx.
    private func post(path: String, body: [String: Any]) async -> Bool {
        guard let url = URL(string: path, relativeTo: config.baseURL)
                     ?? URL(string: config.baseURL.absoluteString + path) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = data
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}

// MARK: - Stranded upload recovery

/// Detects HR rows marked uploaded locally but missing on the server, and resets them.
enum StrandedUploadRecovery {
    private static let minLocalHR = 5_000
    /// HR outage began ~Jul 10 2026 — compare server fill since then vs local store size.
    private static let gapEpochStart = 1_783_634_400

    static func recoverIfNeeded(store: WhoopStore,
                                config: UploaderConfig,
                                deviceId: String) async -> Bool {
        guard let stats = try? await store.hrUploadStats(deviceId: deviceId) else { return false }
        guard stats.total >= minLocalHR, stats.pending == 0 else { return false }

        // Stranded means "the PHONE has rows in the window the server is missing" — so the
        // comparison must be windowed on BOTH sides. Comparing server-in-window against the
        // TOTAL store size false-positives whenever the phone itself has nothing in the window
        // (e.g. the store was just restored FROM the server), and the reset then re-flags the
        // entire restored store for a no-op re-upload, forever, on every connect.
        let localSinceGap = (try? await store.hrCount(deviceId: deviceId, from: gapEpochStart)) ?? 0
        guard localSinceGap >= 10_000 else { return false }

        let now = Int(Date().timeIntervalSince1970)
        let serverSinceGap = await serverHRCount(config: config,
                                               deviceId: deviceId,
                                               from: gapEpochStart,
                                               to: now)
        guard serverSinceGap >= 0 else { return false }
        let threshold = max(10_000, localSinceGap / 20)
        guard serverSinceGap < threshold else { return false }

        return await resetAndLog(store: store, deviceId: deviceId,
                                 reason: "server since gap=\(serverSinceGap) local since gap=\(localSinceGap)")
    }

    /// Inverse pass: a huge pending backlog whose rows the server already has (store restored
    /// from the server, then wrongly re-flagged by an earlier recovery build) is marked back to
    /// synced instead of re-uploaded row by row. Gated on the server holding statistically the
    /// same HR store (count within ±1%) so it can never swallow genuinely unsent rows: any real
    /// local-only backlog makes the phone count exceed the server's and the gate fails.
    static func reconcileIfAlreadyUploaded(store: WhoopStore,
                                           config: UploaderConfig,
                                           deviceId: String) async -> Bool {
        guard let stats = try? await store.hrUploadStats(deviceId: deviceId) else { return false }
        guard stats.pending >= 500_000 else { return false }

        let now = Int(Date().timeIntervalSince1970)
        let serverTotal = await serverHRCount(config: config, deviceId: deviceId, from: 0, to: now)
        guard serverTotal >= 0 else { return false }
        let tolerance = max(1_000, stats.total / 100)
        guard abs(serverTotal - stats.total) <= tolerance else { return false }

        let marked = (try? await store.markAllBiometricStreamSyncFlags(deviceId: deviceId)) ?? 0
        if marked > 0 {
            print("StrandedUploadRecovery: reconciled \(marked) rows already on server "
                  + "(server=\(serverTotal) local=\(stats.total))")
        }
        return marked > 0
    }

    static func forceReset(store: WhoopStore, deviceId: String) async -> Bool {
        await resetAndLog(store: store, deviceId: deviceId, reason: "manual force")
    }

    private static func resetAndLog(store: WhoopStore, deviceId: String, reason: String) async -> Bool {
        let reset = (try? await store.resetBiometricStreamSyncFlags(deviceId: deviceId)) ?? 0
        if reset > 0 {
            print("StrandedUploadRecovery: reset \(reset) rows (\(reason))")
        }
        return reset > 0
    }

    private static func serverHRCount(config: UploaderConfig,
                                      deviceId: String,
                                      from: Int,
                                      to: Int) async -> Int {
        guard let url = URL(string: "/v1/summary?device=\(deviceId)&from=\(from)&to=\(to)",
                            relativeTo: config.baseURL)
                ?? URL(string: "\(config.baseURL.absoluteString)/v1/summary?device=\(deviceId)&from=\(from)&to=\(to)")
        else { return -1 }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hr = obj["hr"] as? NSNumber else { return -1 }
            return hr.intValue
        } catch {
            return -1
        }
    }
}

// MARK: - [UInt8] hex encoding

private extension Array where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
