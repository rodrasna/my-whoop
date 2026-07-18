import Foundation
import Combine

/// Observable snapshot of the live connection + biometric state, driven by FrameRouter
/// (from decoded frames) and BLEManager (from CoreBluetooth callbacks).
/// `@MainActor` so SwiftUI views observe it safely; mutators are called on the main queue.
@MainActor
public final class LiveState: ObservableObject {
    @Published public var connected: Bool = false
    @Published public var bonded: Bool = false
    @Published public var heartRate: Int? = nil
    @Published public var rr: [Int] = []
    @Published public var batteryPct: Double? = nil
    /// Fuel-gauge voltage from GET_EXTENDED_BATTERY_INFO or BATTERY_LEVEL events (millivolts).
    @Published public var batteryMv: Int? = nil
    @Published public var lastFrameType: String? = nil
    @Published public var lastEvent: String? = nil
    /// Unix epoch the strap reports as armed (nil = unknown / disarmed). Set after GET_ALARM_TIME verify.
    @Published public var firmwareAlarmEpoch: UInt32? = nil
    /// True when GET_ALARM_TIME (or STRAP_DRIVEN_ALARM_SET) confirms the target time is on the strap.
    @Published public var firmwareAlarmVerified = false
    /// Rolling log of human-readable lines for the on-device verification checklist.
    @Published public var log: [String] = []

    /// True when the stuck-strap watchdog finds the strap has newer records than us but our frontier
    /// won't advance (likely needs a manual reboot; ~never after high-freq-sync removal). Banner-only.
    @Published public var strapNeedsReboot = false

    /// Wall time (unix seconds) of the last successfully-completed offload (a sync, even if nothing new
    /// came — i.e. caught up). Drives the sync tile + the staleness nudge.
    @Published public var lastSyncedAt: TimeInterval?

    /// True while a type-47 historical offload is draining the strap (may take several minutes).
    @Published public var isOffloading = false

    /// True after several empty offload timeouts in a row: the strap accepted SEND_HISTORICAL but
    /// never streamed HISTORY frames. Auto-sync pauses; UI should NOT keep saying "Descargando…".
    @Published public var offloadStalled = false

    /// Consecutive empty offload timeouts (no HISTORY frames). Reset on progress / complete.
    @Published public var consecutiveOffloadTimeouts = 0

    /// HR rows waiting to POST to the server (`synced = 0` in the local store).
    @Published public var pendingHrUpload = 0

    /// Short user-facing status while a clock-repair sequence runs.
    @Published public var repairStatus: String?

    /// Optional hook invoked on every battery update (wired by LiveViewModel to the alert monitor).
    /// Kept as a closure so LiveState stays a plain observable snapshot with no alert dependency.
    public var onBatteryUpdate: ((Double) -> Void)?

    public init() {}

    /// Single funnel for battery readings — updates the published value AND notifies the hook,
    /// so both write sites (FrameRouter, BLEManager) drive the alert monitor identically.
    public func setBattery(_ pct: Double) {
        batteryPct = pct
        onBatteryUpdate?(pct)
    }

    public func append(log line: String) {
        log.append(line)
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }
}
