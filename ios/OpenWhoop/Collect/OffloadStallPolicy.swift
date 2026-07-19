import Foundation

/// Pure decisions for the historical-offload stall / CLOCK-LOST hold loop.
///
/// Live failure mode (2026-07-18): strap RTC jumps to 2029 → SEND_HISTORICAL dribbles
/// ~50–60 frames then times out → 3 timeouts → "Descarga atascada" → auto repair →
/// HISTORY_COMPLETE with ~10–20 frames clears the stall → another offload → repeat.
///
/// Rules encoded here:
/// 1. HISTORY_COMPLETE must NOT clear a stall while RTC is still known-corrupt.
/// 2. A tiny HISTORY_COMPLETE under corrupt RTC is vacuous (empty/unusable flash), not "caught up".
/// 3. After salvage+repair already ran this episode, another future DATA_RANGE means hold for charger —
///    do not start another salvage/offload storm.
enum OffloadStallPolicy {
    /// Frames at or below this with corrupt RTC ⇒ treat HISTORY_COMPLETE as vacuous.
    static let vacuousHistoryCompleteMaxFrames = 100

    /// Keep auto-sync paused after HISTORY_COMPLETE when the strap clock is still bad.
    static func shouldClearStallOnHistoryComplete(rtcKnownCorrupt: Bool) -> Bool {
        !rtcKnownCorrupt
    }

    /// Tiny complete under corrupt RTC ≠ healthy catch-up (don't advertise "Al día" from it).
    static func isVacuousHistoryComplete(frames: Int, rtcKnownCorrupt: Bool,
                                         maxFrames: Int = vacuousHistoryCompleteMaxFrames) -> Bool {
        rtcKnownCorrupt && frames <= maxFrames
    }

    /// Whether a new CLOCK-LOST salvage offload should run, or we should hold for the charger.
    static func shouldStartSalvage(alreadySalvagedThisEpisode: Bool) -> Bool {
        !alreadySalvagedThisEpisode
    }

    /// User-facing hold copy once salvage/repair have been tried and RTC still won't latch.
    static let clockHoldStatus = "RTC perdido — pon la pulsera al cargador"

    /// Stall banner title when the root cause is RTC, not a generic download jam.
    static let clockHoldBannerTitle = "Reloj de la pulsera perdido"

    static let clockHoldBannerBody =
        "La pulsera sigue con el reloj muerto (DATA_RANGE en el futuro o mudo). "
        + "La app oficial y Reparar no lo han latchado. Déjala EN el cargador 30+ min "
        + "sin la app oficial abierta. Si sigue así: agota batería a 0, carga, abre solo OpenWhoop "
        + "y pulsa Reparar una vez."

    /// How long to wait after connect for a fresh DATA_RANGE / GET_CLOCK before re-asserting hold.
    /// Official WHOOP (or a soft repair) may have latched RTC while we still had a persisted hold —
    /// re-entering hold at 1.5s from stale state blocked that probe (2026-07-19).
    static let rtcProbeTimeoutSeconds: TimeInterval = 8

    /// Extra wait after an empty DATA_RANGE while SET_CLOCK may still be settling post-reboot.
    static let rtcProbeExtendSeconds: TimeInterval = 20

    /// Max empty-DATA_RANGE extensions per probe episode (avoid infinite wait).
    static let rtcProbeMaxExtensions = 2

    /// While a persisted/episode hold is active, connect should await a fresh probe — not
    /// immediately re-enter hold and skip listening for a sane DATA_RANGE.
    static func shouldAwaitDataRangeProbe(holdActive: Bool) -> Bool {
        holdActive
    }

    /// Empty DATA_RANGE during probe: keep waiting (and pulse SET_CLOCK) instead of holding yet.
    static func shouldExtendProbeOnEmptyDataRange(extensionsUsed: Int,
                                                  maxExtensions: Int = rtcProbeMaxExtensions) -> Bool {
        extensionsUsed < maxExtensions
    }

    /// Status while we wait for the strap to answer GET_DATA_RANGE after official sync / Reparar.
    static let rtcProbeStatus = "Comprobando reloj de la pulsera…"
}
