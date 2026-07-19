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
        "La pulsera no graba con un reloj válido — por eso la descarga no avanza. "
        + "OpenWhoop ya no reintenta sola. Déjala EN el cargador, pulsa Reparar una vez, "
        + "y espera 10+ min sin quitarla. Si el mensaje no cae, el soft repair no basta."
}
