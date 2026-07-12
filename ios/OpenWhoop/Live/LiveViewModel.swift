import Foundation
import Combine
import WhoopProtocol

/// Owns the LiveState + BLEManager and exposes intent methods for the LiveView.
@MainActor
public final class LiveViewModel: ObservableObject {
    public let state: LiveState
    private let ble: BLEManager
    private let batteryAlerts = BatteryAlertMonitor()
    private var cancellables = Set<AnyCancellable>()

    /// One-line storage summary for the UI; refreshed periodically from LiveView.
    @Published public var storageSummary: String = "stored: —"

    public init(deviceId: String = "my-whoop") {
        let s = LiveState()
        self.state = s
        self.ble = BLEManager(state: s, deviceId: deviceId)
        // Drive battery alerts off every reading (foreground or background, while the process lives).
        s.onBatteryUpdate = { [batteryAlerts] pct in batteryAlerts.handle(battery: pct) }
        // Request notification permission for all local notifications in one pass — sync nudge and
        // morning recovery. iOS only prompts the user once (subsequent calls are no-ops after the
        // user has decided), so calling both here keeps all auth in one place.
        // Skipped under -demoPreview so screenshot captures aren't covered by the auth dialog.
        if !ProcessInfo.processInfo.arguments.contains("-demoPreview") {
            SyncNudge.requestAuthorization()
            RecoveryNotifier.requestAuthorization()
            AlarmNotifier.requestAuthorization()
        }
        s.$lastSyncedAt
            .compactMap { $0 }
            .sink { _ in SyncNudge.reschedule() }
            .store(in: &cancellables)
        ble.onStrapReady = { [weak self] in
            Task { @MainActor in self?.restoreStrapAlarmIfNeeded() }
        }
        ble.onFirmwareAlarmResult = { [weak self] fireDate, verified in
            Task { @MainActor in self?.handleFirmwareAlarmResult(fireDate: fireDate, verified: verified) }
        }
        state.$bonded
            .filter { $0 }
            .sink { [weak self] _ in
                Task { @MainActor in self?.restoreStrapAlarmIfNeeded() }
            }
            .store(in: &cancellables)
        reschedulePendingAlarmFromStorage()
    }

    public func connect()  { ble.connect() }
    public func disconnect() { ble.disconnect() }
    public func startRealtimeHR() { ble.send(.toggleRealtimeHR, payload: [0x01]) }
    public func stopRealtimeHR()  { ble.send(.toggleRealtimeHR, payload: [0x00]) }
    public func getBattery()      { ble.send(.getBatteryLevel,  payload: [0x00]) }
    public func getExtendedBattery() { ble.send(.getExtendedBatteryInfo, payload: [0x00]) }

    /// Fire a preset haptic pattern on the strap (makes it buzz). `pattern` indexes the device's
    /// preset patterns; `loops` is the repeat count. Confirmed write so the strap acks it.
    public func runHaptic(pattern: UInt8, loops: UInt8) {
        ble.send(.runHapticsPattern, payload: [pattern, loops, 0, 0, 0], writeType: .withResponse)
    }
    public func stopHaptics() { ble.send(.stopHaptics, payload: [0x00], writeType: .withResponse) }

    /// Fire an immediate alarm-pattern buzz on the strap for testing (M6).
    /// Uses runHapticsPattern(patternId=2, loops=3) + runAlarm — same as the official WHOOP app.
    /// Cannot be verified in the simulator (no strap motor); test on-device only.
    public func testAlarmBuzz() { ble.testAlarmBuzz() }

    /// On-demand bounded raw-accel capture (type-43 IMU) for `seconds`, then auto-stop + upload.
    /// Works even when the research toggle is off — that's the point: a one-off activity sample.
    public func captureActivitySample(seconds: TimeInterval = 30) { ble.captureRawAccel(seconds: seconds) }

    // MARK: - Alarm passthroughs (M6)
    // These delegate directly to the private BLEManager so alarm UI never needs a raw
    // BLEManager reference. SmartAlarmController.schedule() still receives the BLEManager
    // directly (it holds it weakly); we hand it ours via armStrapAlarm(at:).

    /// Arm firmware alarm (best-effort) + in-app timer + local notification.
    @discardableResult
    public func armStrapAlarm(at date: Date, smartWake: Bool = false, leadMinutes: Int = 20) -> Bool {
        guard date.timeIntervalSinceNow > 5 else { return false }
        scheduleLocalAlarm(at: date, smartWake: smartWake, leadMinutes: leadMinutes)
        _ = ble.armStrapAlarm(at: date)
        return true
    }

    private func scheduleLocalAlarm(at date: Date, smartWake: Bool, leadMinutes: Int) {
        StrapAlarmScheduler.shared.schedule(at: date) { [weak self] in
            self?.ble.testAlarmBuzz()
        }
        AlarmNotifier.schedule(at: date)
        let lead = max(5, leadMinutes)
        let minutesUntil = date.timeIntervalSinceNow / 60.0
        if smartWake && minutesUntil >= Double(lead) {
            SmartAlarmController.shared.schedule(wakeBy: date, leadMinutes: lead, ble: ble)
        } else {
            SmartAlarmController.shared.cancel()
        }
    }

    /// Re-arm app timer + notification after cold start (no BLE required).
    private func reschedulePendingAlarmFromStorage() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AlarmKeys.enabled) else { return }
        let fireDate = AlarmKeys.nextFireDate(
            hour: defaults.integer(forKey: AlarmKeys.wakeByHour),
            minute: defaults.integer(forKey: AlarmKeys.wakeByMinute)
        )
        guard fireDate.timeIntervalSinceNow > 5 else { return }
        let smartWake = defaults.bool(forKey: AlarmKeys.smartWakeEnabled)
        let lead = defaults.integer(forKey: AlarmKeys.smartWakeLeadMin)
        scheduleLocalAlarm(at: fireDate, smartWake: smartWake, leadMinutes: lead)
    }

    /// Whether the strap accepted an arm request (connected + handshake done).
    public var canArmStrapAlarm: Bool { ble.isStrapReadyForCommands }

    /// Last firmware verification from GET_ALARM_TIME on the strap.
    public var firmwareAlarmVerified: Bool { state.firmwareAlarmVerified }

    private func handleFirmwareAlarmResult(fireDate: Date, verified: Bool) {
        guard UserDefaults.standard.bool(forKey: AlarmKeys.enabled) else { return }
        if verified {
            UserDefaults.standard.set(fireDate.timeIntervalSince1970, forKey: AlarmKeys.armedEpoch)
        }
    }

    /// Disarm the currently-armed firmware alarm and cancel the in-app buzz timer.
    @discardableResult
    public func disableStrapAlarm() -> Bool {
        StrapAlarmScheduler.shared.cancel()
        AlarmNotifier.cancel()
        SmartAlarmController.shared.cancel()
        return ble.disableStrapAlarm()
    }

    /// Re-program the firmware alarm after connect if UserDefaults still has one enabled.
    public func restoreStrapAlarmIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AlarmKeys.enabled) else { return }
        let hour = defaults.integer(forKey: AlarmKeys.wakeByHour)
        let minute = defaults.integer(forKey: AlarmKeys.wakeByMinute)
        // Always schedule the *next* occurrence — armedEpoch may be this morning's fire time.
        let fireDate = AlarmKeys.nextFireDate(hour: hour, minute: minute)
        let smartWake = defaults.bool(forKey: AlarmKeys.smartWakeEnabled)
        let lead = defaults.integer(forKey: AlarmKeys.smartWakeLeadMin)
        scheduleLocalAlarm(at: fireDate, smartWake: smartWake, leadMinutes: lead)
        if ble.armStrapAlarm(at: fireDate) {
            defaults.set(fireDate.timeIntervalSince1970, forKey: AlarmKeys.armedEpoch)
        }
    }

    /// Request the current alarm time from the strap.
    public func getStrapAlarm() { ble.getStrapAlarm() }

    // MARK: - Lifecycle

    /// Apply raw-outbox retention when the app backgrounds (wired via scenePhase).
    public func onEnterBackground() {
        ble.pruneRaw()
        SyncNudge.reschedule()
    }

    /// App became active — opportunistically sync (rate-limited; won't hammer on rapid toggles).
    public func enterForeground() {
        restoreStrapAlarmIfNeeded()
        ble.requestSync(.foreground)
    }
    /// User tapped "Sync now" — force an offload regardless of the periodic floor.
    public func syncNow() { ble.requestSync(.manual) }

    public func forceReupload() {
        Task { await ble.forceReuploadBiometrics() }
    }

    /// Refresh the storage summary line from the store (polled every few seconds by LiveView).
    public func refreshStorage() {
        Task { @MainActor in
            guard let s = await ble.storageStats() else { storageSummary = "stored: —"; return }
            let mb = Double(s.rawBytes) / (1024 * 1024)
            storageSummary = String(format: "HR %d almac · %d pend · total %d · %.1f MB raw",
                                    s.hrTotal, s.pendingHR, s.decodedRows, mb)
        }
    }
}
