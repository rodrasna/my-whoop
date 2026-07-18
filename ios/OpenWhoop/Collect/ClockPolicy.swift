import Foundation

/// Pure decision: should we SET_CLOCK on this connect? Mirrors WHOOP — set only when the strap's RTC
/// has drifted beyond a small threshold (or is frozen/way off), not blindly every connect. Avoids
/// gratuitous clock resets that could introduce discontinuities in derived historical timestamps.
enum ClockPolicy {
    /// `deviceClock` = the strap's current RTC reading (unix seconds, from GET_CLOCK). `wallNow` =
    /// phone wall time (unix seconds). Returns true if |drift| >= threshold.
    static func shouldSetClock(deviceClock: Int, wallNow: Int, driftThreshold: Int = 2) -> Bool {
        abs(wallNow - deviceClock) >= driftThreshold
    }

    /// Max how far ahead of phone wall a stored RECORD timestamp may be and still look sane.
    /// Markers in 2029/2030 fail this — classic CLOCK-LOST symptom on this hardware.
    static let maxFutureSkewSeconds: Int = 86_400          // 1 day
    /// How far behind wall a "newest" marker may be. Wide on purpose: second-hand / idle straps
    /// can have months-old flash without a lost RTC. Future skew is the strong signal.
    static let maxPastSkewSeconds: Int = 180 * 86_400      // 180 days

    /// True when `ts` is a plausible wall-relative unix (not years in the future / distant past).
    static func isSaneWallRelative(_ ts: Int, wallNow: Int,
                                   maxFuture: Int = maxFutureSkewSeconds,
                                   maxPast: Int = maxPastSkewSeconds) -> Bool {
        let skew = ts - wallNow
        return skew <= maxFuture && skew >= -maxPast
    }

    /// Strong CLOCK-LOST signal: strap reports stored records in the future vs phone wall.
    static func isFutureCorrupt(strapNewest: Int?, wallNow: Int,
                                maxFuture: Int = maxFutureSkewSeconds) -> Bool {
        guard let newest = strapNewest else { return false }
        return newest - wallNow > maxFuture
    }

    /// DATA_RANGE evidence that markers are unusable for liveness (future OR absurdly old).
    static func isClockLost(strapNewest: Int?, wallNow: Int) -> Bool {
        guard let newest = strapNewest else { return true }
        return !isSaneWallRelative(newest, wallNow: wallNow)
    }
}
