import Foundation
import CoreBluetooth
import WhoopProtocol
import WhoopStore

/// CoreBluetooth engine for the WHOOP 4.0: scan-by-service → connect → discover →
/// BOND (one confirmed write) → subscribe → reassemble char-05 frames → FrameRouter.
/// Cannot run in the simulator; verified manually on-device (Task C6).
@MainActor
public final class BLEManager: NSObject, ObservableObject {

    // MARK: GATT UUIDs (authoritative, from FINDINGS.md)
    static let customService   = CBUUID(string: "61080001-8d6d-82b8-614a-1c8cb0f8dcc6")
    static let cmdWriteChar    = CBUUID(string: "61080002-8d6d-82b8-614a-1c8cb0f8dcc6") // CMD → strap
    static let cmdNotifyChar   = CBUUID(string: "61080003-8d6d-82b8-614a-1c8cb0f8dcc6") // responses
    static let eventNotifyChar = CBUUID(string: "61080004-8d6d-82b8-614a-1c8cb0f8dcc6") // events
    static let dataNotifyChar  = CBUUID(string: "61080005-8d6d-82b8-614a-1c8cb0f8dcc6") // data (frag)
    static let heartRateService = CBUUID(string: "180D")
    static let heartRateChar    = CBUUID(string: "2A37") // HR + R-R (works unbonded)
    static let batteryService   = CBUUID(string: "180F")
    static let batteryChar      = CBUUID(string: "2A19")

    static let restoreID = "com.openwhoop.ble.central"

    // MARK: Published state
    public let state: LiveState
    private let router: FrameRouter
    private var collector: Collector?
    private var whoopStore: WhoopStore?

    // MARK: Upload
    private var uploader: Uploader?

    // MARK: Server pull (History = union(phone-collected, server-computed))
    private var serverSync: ServerSync?
    /// Guards the once-per-launch cloud restore attempt so it does not re-run on every reconnect.
    /// `restoreIfEmpty()` is already self-gating via the emptiness check, but this flag avoids a
    /// redundant round-trip on every connect once we know the store is non-empty.
    private var didAttemptRestore = false

    // MARK: Backfill
    private var backfiller: Backfiller?
    /// True while a historical offload session is in progress (frames route to Backfiller).
    private var backfilling = false
    /// Safety-net detector: strap reports newer data than us AND our frontier frozen 10 min ⇒ flag for
    /// reboot. behindGapSeconds avoids false positives when off-wrist / caught up. Insurance only.
    private var stuckDetector = StuckStrapDetector(stuckAfterSeconds: 600, behindGapSeconds: 300)
    /// One-shot guard for the `-repairStrap` launch arg (a reboot drops the link and reconnects
    /// within the same process — without this the arg would reboot in a loop).
    private var didSendRepairReboot = false
    /// `-bleDebug` launch arg: dump raw COMMAND_RESPONSE frames to the log.
    private lazy var bleDebug = ProcessInfo.processInfo.arguments.contains("-bleDebug")
    /// Newest record unix the strap reports having (from the GET_DATA_RANGE response); refreshed each
    /// offload. Compared against our frontier to tell "stuck" from "off-wrist/caught-up".
    private var strapNewestTs: Int?
    /// Offload frames (47/48/49/50) seen in the current session — empty + timeout ⇒ stall candidate.
    private var offloadFramesThisSession = 0
    /// After this many consecutive empty timeouts, pause auto-sync and surface a clear stall state.
    static let offloadStallAfterTimeouts = 3
    /// Auto CLOCK-LOST repair (SET_CLOCK + reboot) at most once per connection, and not more often
    /// than this cooldown (survives reconnect storms when RTC won't latch).
    static let autoRepairCooldownSeconds: TimeInterval = 600
    static let autoRepairLastAtKey = "autoRepairLastAt"
    private var didAutoRepairThisConnection = false
    /// Set when repairStrapClock reboots the strap; the next connect may clear stall for one attempt.
    private var pendingRepairReconnect = false
    /// After CLOCK-LOST detect: run one remapped salvage offload, then repair.
    private var pendingRepairAfterSalvage = false
    private var didSalvageThisClockLoss = false
    /// True while DATA_RANGE (or an open episode) shows an unusable/future strap RTC.
    /// Survives HISTORY_COMPLETE so we don't clear stall and restart the offload loop.
    private var rtcKnownCorrupt = false
    private var salvageDeadline: DispatchWorkItem?
    /// Max time to wait for salvage offload before forcing SET_CLOCK + reboot.
    static let clockLossSalvageTimeoutSeconds = 90
    /// Fires if the strap goes silent mid-offload; re-armed on every frame during backfill.
    private var backfillTimeout: DispatchWorkItem?
    /// Periodic opportunistic upload while connected. Without it, upload only fires at connect +
    /// backfill-exit, so during a long live session decoded rows pile up locally and the server
    /// (dashboard) lags. Started on bond, cancelled on disconnect.
    private var uploadTimer: DispatchSourceTimer?
    static let uploadIntervalSeconds = 30
    /// Periodic re-trigger of the type-47 historical offload. This is the PRIMARY continuous metric
    /// source (mirrors how WHOOP syncs): the strap's 14-day biometric store is re-offloaded every
    /// `backfillIntervalSeconds` while connected+bonded, rather than once per connect. Started on
    /// bond, cancelled on disconnect. Plain SEND_HISTORICAL_DATA returns the type-47 store (no
    /// high-freq-sync), so each periodic tick just routes through requestSync(.periodic) → beginBackfill
    /// (SEND_HISTORICAL_DATA + watchdog), subject to the BackfillPolicy floor.
    private var backfillTimer: DispatchSourceTimer?
    // The timer fires this often, but BackfillPolicy.periodicFloorSeconds is the real floor (a recent
    // event-triggered sync defers the next periodic tick). 900s = 15 min, matching WHOOP.
    static let backfillIntervalSeconds = 900
    /// Last-offload-attempt time (unix seconds), persisted so the rate limiter survives relaunch
    /// (matches WHOOP's DATA_SYNC_WORKER_LAST_WORK_TIME watermark).
    static let backfillLastAtKey = "backfillLastAt"
    /// Prevents a second backfill from starting on a same-process reconnect to the same strap.
    private var backfillStarted = false
    /// Runs the connect handshake EXACTLY ONCE per connection. `didWriteValueFor` re-fires on every
    /// `.withResponse` write (the bond write, every SEND_HISTORICAL, every HISTORY_END ack); without
    /// this guard those re-entries re-blasted hello/SET_CLOCK at the strap mid-offload and stopped it
    /// from streaming type-47 — THE iOS "won't serve" root cause. Reset on disconnect.
    private var connectHandshakeDone = false
    /// Called once per BLE connect after the handshake (hello, SET_CLOCK, …) completes.
    var onStrapReady: (() -> Void)?
    /// `(fireDate, verified)` — verified=true when GET_ALARM_TIME matches the target.
    var onFirmwareAlarmResult: ((Date, Bool) -> Void)?

    // MARK: Firmware alarm arming (sequenced SET_CLOCK → SET_ALARM → GET_ALARM verify)
    private struct PendingArm {
        let targetEpoch: UInt32
        let fireDate: Date
        var attempt: Int
    }
    private enum ArmPhase: Equatable {
        case idle, disabling, settingClock, clockSettling, settingAlarm(UInt32), verifying(UInt32)
    }
    private var pendingArm: PendingArm?
    private var armPhase: ArmPhase = .idle
    private var armStepTimer: DispatchWorkItem?
    private static let maxArmAttempts = 3

    /// True when alarm commands can be sent to the strap.
    var isStrapReadyForCommands: Bool {
        peripheral != nil && cmdCharacteristic != nil && connectHandshakeDone
    }
    /// Re-entrancy guard for captureRawAccel: true while a bounded on-demand window is running.
    /// A second tap is a no-op until the active capture's asyncAfter block fires and clears this.
    private var rawCaptureInFlight = false
    /// Ordered queue of frames awaiting drain through the serial Backfiller task.
    private var backfillFrameQueue: [[UInt8]] = []
    /// True while the drain task is running (prevents a second drain task from launching).
    private var backfillDraining = false

    // MARK: CoreBluetooth
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    /// Peripheral captured during `willRestoreState`; cleared in `didConnect`.
    /// Non-nil signals that `centralManagerDidUpdateState` should reconnect this
    /// specific peripheral rather than starting a fresh scan.
    private var restoredPeripheral: CBPeripheral?
    private var cmdCharacteristic: CBCharacteristic?
    private let reassembler = Reassembler()
    private var seq: UInt8 = 0
    private var didBond = false
    private var clockRequested = false
    private var intentionalDisconnect = false

    /// Stable device id; matches the server's existing device for sync parity. Overridable.
    let deviceId: String
    /// Captured (device↔wall) correlation from GET_CLOCK; nil until the response lands.
    private(set) var clockRef: ClockRef?

    public init(state: LiveState, deviceId: String = "my-whoop") {
        self.state = state
        self.deviceId = deviceId
        self.router = FrameRouter(state: state)
        // WhoopStore.init is now async, so it can't run here.
        // bootstrapStore() is called once the CBCentralManager reaches poweredOn
        // (see centralManagerDidUpdateState), which guarantees the store is ready
        // before any BLE data arrives.
        self.collector = nil
        super.init()
        state.lastSyncedAt = UserDefaults.standard.object(forKey: "lastSyncedAt") as? Double
        // Restore identifier + background-capable central (foundation for M3 state restoration).
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: BLEManager.restoreID]
        )
        // Strap-as-clock: an incoming EVENT packet kicks a rate-limited catch-up sync.
        router.onSyncTrigger = { [weak self] in self?.requestSync(.strap) }
        router.onFirmwareAlarmEvent = { [weak self] ev in self?.handleFirmwareAlarmEvent(ev) }
    }

    /// Build the WhoopStore + Collector + Backfiller asynchronously. Safe to call multiple
    /// times — bails out early if the collector is already initialised.
    func bootstrapStore() async {
        guard collector == nil else { return }
        guard let path = try? StorePaths.defaultDatabasePath() else { return }
        guard let store = try? await WhoopStore(path: path) else { return }
        whoopStore = store
        try? await store.upsertDevice(id: deviceId, mac: nil, name: "WHOOP 4.0")
        // Research toggle — OFF by default. When disabled the app is decoded-only and never
        // persists raw frames. Flip "enableRawCapture" in UserDefaults to capture raw again.
        let enableRawCapture = UserDefaults.standard.bool(forKey: "enableRawCapture")
        collector = Collector(store: store, deviceId: deviceId,
                              enableRawCapture: enableRawCapture)
        backfiller = Backfiller(store: store, deviceId: deviceId,
                                ackTrim: { [weak self] trim, endData in
                                    self?.ackHistoricalChunk(trim: trim, endData: endData)
                                },
                                enableRawCapture: enableRawCapture)
        if let cfg = AppConfig.uploaderConfig() {
            uploader = Uploader(config: cfg, store: store, deviceId: deviceId)
            serverSync = ServerSync(config: cfg, store: store, deviceId: deviceId)
        }
        if let ref = clockRef {
            collector?.clockRef = ref
            backfiller?.clockRef = ref
        }
        await recoverStrandedUploadsIfNeeded()
    }

    /// Rows can be marked synced locally even though the server never received them (timeouts /
    /// all-skipped batches on older builds). Reset and re-drain when local HR is large, nothing
    /// pending, and the server has had no HR recently.
    private func recoverStrandedUploadsIfNeeded() async {
        guard let store = whoopStore, let cfg = AppConfig.uploaderConfig() else { return }
        // Inverse pass first: a backlog the server already has is marked synced, not re-sent.
        let reconciled = await StrandedUploadRecovery.reconcileIfAlreadyUploaded(
            store: store, config: cfg, deviceId: deviceId)
        if reconciled {
            log("Upload recovery: pending backlog already on server — marked synced")
        }
        let recovered = await StrandedUploadRecovery.recoverIfNeeded(
            store: store, config: cfg, deviceId: deviceId)
        if recovered {
            log("Upload recovery: reset stranded biometric rows — starting drain")
        }
        await drainPendingUploadsIfAny()
    }

    /// Force all biometric rows back to pending upload (Device tab manual recovery).
    func forceReuploadBiometrics() async {
        guard let store = whoopStore else {
            log("Force re-upload: store not ready")
            return
        }
        let ok = await StrandedUploadRecovery.forceReset(store: store, deviceId: deviceId)
        log(ok ? "Force re-upload: rows reset — draining" : "Force re-upload: nothing to reset")
        await drainPendingUploadsIfAny()
    }

    private func drainPendingUploadsIfAny() async {
        guard let store = whoopStore else { return }
        if let stats = try? await store.hrUploadStats(deviceId: deviceId), stats.pending > 0 {
            state.pendingHrUpload = stats.pending
            log("Upload drain: \(stats.pending) HR rows pending")
        } else {
            state.pendingHrUpload = 0
        }
        // Always kick drain: gravity/skin/resp can still be pending after HR hits zero,
        // and sleep detection on the server needs gravity.
        uploadOpportunistically()
    }

    /// Designated initializer for testing and preview use: accepts a pre-built Collector.
    init(state: LiveState, deviceId: String = "my-whoop", collector: Collector?) {
        self.state = state
        self.deviceId = deviceId
        self.router = FrameRouter(state: state)
        self.collector = collector
        super.init()
        state.lastSyncedAt = UserDefaults.standard.object(forKey: "lastSyncedAt") as? Double
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: BLEManager.restoreID]
        )
        // Strap-as-clock: an incoming EVENT packet kicks a rate-limited catch-up sync.
        router.onSyncTrigger = { [weak self] in self?.requestSync(.strap) }
        router.onFirmwareAlarmEvent = { [weak self] ev in self?.handleFirmwareAlarmEvent(ev) }
    }

    // MARK: Public API
    public func connect() {
        intentionalDisconnect = false
        guard central.state == .poweredOn else {
            log("Bluetooth not powered on (state=\(central.state.rawValue)); cannot scan yet")
            return
        }
        log("Scanning for service \(BLEManager.customService)…")
        central.scanForPeripherals(
            withServices: [BLEManager.customService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    public func disconnect() {
        intentionalDisconnect = true
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        central.stopScan()
    }

    /// Apply the raw-outbox retention policy (24h synced window / 50MB unsynced cap).
    /// Called when the app enters the background; no-op without a concrete store.
    public func pruneRaw() {
        Task { @MainActor in await collector?.prune() }
    }

    /// Light storage summary for the UI (decoded rows, raw batches, raw bytes, HR pending). nil without a store.
    public func storageStats() async -> (decodedRows: Int, rawBatches: Int, rawBytes: Int, hrTotal: Int, pendingHR: Int)? {
        guard let base = await collector?.storageStats() else { return nil }
        let hr = (try? await whoopStore?.hrUploadStats(deviceId: deviceId)) ?? (total: 0, pending: 0)
        return (base.decodedRows, base.rawBatches, base.rawBytes, hr.total, hr.pending)
    }

    /// Capture raw accelerometer (type-43 IMU) frames on demand for a bounded window, then stop.
    /// Persists raw even when the global research toggle is off (that's the point: on-demand, not
    /// 24/7). The Collector's window auto-expires at its deadline so a dropped stop can't leak raw.
    public func captureRawAccel(seconds: TimeInterval = 30) {
        guard !rawCaptureInFlight else {
            log("Raw-accel capture: already in flight — ignoring")
            return
        }
        rawCaptureInFlight = true
        let secs = RawCaptureWindow.clamp(seconds)
        collector?.beginRawCapture(seconds: secs)
        send(.startRawData, payload: [0x01])
        send(.toggleIMUMode, payload: [0x01])
        log("Raw-accel capture: started for \(secs)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + secs) { [weak self] in
            guard let self else { return }
            // Only stop the raw stream if the 24/7 research toggle is OFF.  When it's ON, the
            // continuous stream must keep running — we just flush/upload the bounded window we
            // captured without halting the wider session.
            if !UserDefaults.standard.bool(forKey: "enableRawCapture") {
                self.send(.stopRawData, payload: [0x01])
            }
            self.rawCaptureInFlight = false
            Task { @MainActor in
                await self.collector?.endRawCapture()
                self.uploadOpportunistically()   // push the captured raw to the server
            }
            self.log("Raw-accel capture: stopped + flushed")
        }
    }

    /// Send a command to the WHOOP strap.
    /// - Parameters:
    ///   - command: The command to send.
    ///   - payload: Command payload bytes (default `[0x00]`).
    ///   - writeType: BLE write type; defaults to `.withoutResponse` so all existing call
    ///     sites are unaffected. Pass `.withResponse` for acked commands (e.g. historicalDataResult).
    public func send(_ command: WhoopCommand, payload: [UInt8] = [0x00],
                     writeType: CBCharacteristicWriteType = .withoutResponse) {
        guard let p = peripheral, let ch = cmdCharacteristic else {
            log("send(\(command.label)) ignored — not connected")
            return
        }
        seq = seq &+ 1
        let frame = command.frame(seq: seq, payload: payload)
        p.writeValue(Data(frame), for: ch, type: writeType)
        log("→ \(command.label) payload=\(hex(payload))")
    }

    /// Ack one HISTORY_END chunk so the strap may trim it. Confirmed write — the strap forgets
    /// the chunk once this lands (link-layer half of safe-trim; decoded + raw already persisted).
    ///
    /// High-freq-sync ack form (matches re/sync_openwhoop.py, which pulled 762 type-47 records):
    /// HISTORICAL_DATA_RESULT(23) payload = `[0x01] + end_data`, where end_data is the verbatim
    /// 8 bytes of the HISTORY_END metadata.data[10:18] (trim u32 at [10:14] + next u32 at [14:18]).
    /// The `trim` argument (= end_data first u32) is already persisted as the strap_trim cursor by
    /// the Backfiller; it is passed here only for logging.
    func ackHistoricalChunk(trim: UInt32, endData: [UInt8]) {
        send(.historicalDataResult, payload: [0x01] + endData, writeType: .withResponse)
    }

    // MARK: Backfill helpers

    /// Start a historical-offload session: tell the store machine to begin, flip the routing
    /// flag, kick the strap with sendHistoricalData, and arm the idle timeout.
    private func beginBackfill(forceDespiteStall: Bool = false) {
        if state.offloadStalled, !forceDespiteStall {
            log("Backfill: blocked — stalled (use Reparar pulsera or Sync now)")
            return
        }
        // Never offload before the connect handshake has run: a racing foreground/restore trigger
        // firing SEND_HISTORICAL ahead of hello/SET_CLOCK was part of the storm that stopped serving.
        guard connectHandshakeDone else {
            log("Backfill: deferred — connect handshake not done yet")
            return
        }
        guard let backfiller else {
            // Store not ready yet. Do NOT force live HR — the type-47 backfill is the metric
            // source. Just log; the next periodic backfill tick will run once the store is ready.
            log("Backfill: store not ready — deferring to next periodic tick")
            return
        }
        backfiller.begin()
        backfilling = true
        offloadFramesThisSession = 0
        state.isOffloading = true
        // Payload MUST be [0x00], NOT empty: verified on-device that this strap serves type-47 only with
        // [0x00] (empty → 0 frames on a clean stable link with ~2k records pending); the Mac ground-truth
        // offload (re/sync_openwhoop.py, re/diagnose_biometrics.py) uses [0x00] too. Plain offload — the
        // strap streams HISTORY_START → type-47 records → HISTORY_END (acked) … → HISTORY_COMPLETE.
        send(.sendHistoricalData, payload: [0x00], writeType: .withResponse)
        armBackfillTimeout()
        log("Backfill: session started — historical offload requested")
    }

    /// Feed a frame to the Backfiller preserving exact arrival order. Frames are appended
    /// synchronously (delegate order) and drained sequentially by a single task, so START /
    /// data / END chunk assembly is never reordered (Backfiller.ingest is async).
    private func routeBackfillFrame(_ frame: [UInt8]) {
        backfillFrameQueue.append(frame)
        guard !backfillDraining else { return }
        backfillDraining = true
        Task { @MainActor in
            while !backfillFrameQueue.isEmpty {
                let f = backfillFrameQueue.removeFirst()
                await backfiller?.ingest(f)
                afterBackfillIngest()
            }
            backfillDraining = false
        }
    }

    /// Called after every Backfiller.ingest completes. If the Backfiller has consumed all
    /// historical data (isBackfilling drops to false), exit the backfill session cleanly.
    private func afterBackfillIngest() {
        guard backfilling, backfiller?.isBackfilling == false else { return }
        exitBackfilling(reason: "HISTORY_COMPLETE")
    }

    /// True when a frame is part of the historical offload (HISTORICAL_DATA=47, EVENT=48,
    /// METADATA=49, CONSOLE_LOGS=50) rather than the live stream (REALTIME_DATA=40,
    /// REALTIME_RAW_DATA=43). The live type-43 raw flood streams continuously and unprompted on
    /// this firmware, so the backfill idle-watchdog must NOT be re-armed by it — only by genuine
    /// offload progress — otherwise the session can neither complete nor time out.
    static func isOffloadFrame(_ frame: [UInt8]) -> Bool {
        guard frame.count > 4 else { return false }
        switch frame[4] {
        case 47, 48, 49, 50: return true   // HISTORICAL_DATA / EVENT / METADATA / CONSOLE_LOGS
        default: return false              // 40 REALTIME_DATA, 43 REALTIME_RAW_DATA (live flood)
        }
    }

    /// Re-arm the idle watchdog. Called on every offload frame during backfill so the timer resets
    /// as long as the strap keeps sending HISTORY; if the strap goes silent the timer fires and we
    /// exit the session (the durable strap_trim cursor means the next session resumes where we left
    /// off). Timeout is generous (60 s, not 20 s): the unstoppable ~2/s type-43 raw flood eats BLE
    /// airtime, so genuine offload frames can arrive in bursts with multi-second lulls between chunks
    /// — a short watchdog cut sessions short mid-drain. Longer = more records drained per session.
    static let backfillIdleTimeoutSeconds = 60
    private func armBackfillTimeout() {
        backfillTimeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.backfiller?.timeoutFired()
            self.exitBackfilling(reason: "timeout")
        }
        backfillTimeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(BLEManager.backfillIdleTimeoutSeconds), execute: item)
    }

    /// Tear down the backfill session. Does NOT auto-start live HR: the periodic type-47 backfill
    /// is the primary metric source now, mirroring how WHOOP syncs. Live HR is opt-in only (the
    /// manual "Start HR" button in LiveView). Between backfills the Collector sees only the live
    /// type-43 flood, which extractStreams ignores — the data comes from the next periodic offload.
    private func exitBackfilling(reason: String) {
        guard backfilling else { return }
        backfilling = false
        state.isOffloading = false
        backfillTimeout?.cancel()
        backfillTimeout = nil
        backfillFrameQueue.removeAll()
        let framesSeen = offloadFramesThisSession
        log("Backfill: session ended — reason=\(reason) frames=\(framesSeen)")
        noteOffloadOutcome(reason: reason, framesSeen: framesSeen)
        offloadFramesThisSession = 0
        persistClockLossSalvageStats()
        if pendingRepairAfterSalvage {
            finishSalvageAndRepair(reason: "after salvage \(reason)")
        }
        uploadOpportunistically()
        // Read-path sync runs AFTER the offload, never concurrently with it — the offload and the
        // pull share the WhoopStore actor, and a large first-run pull would starve the Backfiller's
        // per-chunk insert→ack and trip the 20s offload watchdog. Safe to run now: backfilling=false.
        restoreFromServerIfNeeded()  // once-per-launch: full history restore if the store is empty
        pullFromServer()             // incremental pull: new rows since read-highwater
        // Vacuous HISTORY_COMPLETE under corrupt RTC is not a real catch-up — don't paint "Al día".
        if reason == "HISTORY_COMPLETE",
           !OffloadStallPolicy.isVacuousHistoryComplete(frames: framesSeen,
                                                        rtcKnownCorrupt: rtcKnownCorrupt) {
            state.lastSyncedAt = Date().timeIntervalSince1970
            UserDefaults.standard.set(state.lastSyncedAt, forKey: "lastSyncedAt")
        }
        flushPendingArmIfNeeded()
        checkStrapLiveness()         // safety-net: strap ahead of us AND our frontier frozen ⇒ stuck?
    }

    // MARK: - CLOCK-LOST salvage + forensic timeline

    /// Detected future DATA_RANGE: persist an event, arm remap, try one salvage offload, then repair.
    private func handleClockLost(newest: Int, oldest: Int?, wall: Int, reason: String) {
        rtcKnownCorrupt = true
        state.strapNeedsReboot = true
        state.lastClockLossDetectedAt = TimeInterval(wall)
        state.clockLossStatus = "RTC perdido — intentando recuperar histórico…"
        log("Clock lost: \(reason) newest=\(newest) wall=\(wall) Δ≈\(newest - wall)s")

        Task { @MainActor in
            let frontier = try? await whoopStore?.cursor("hist_hr_frontier")
            let open = try? await whoopStore?.openClockLossEvent(deviceId: deviceId)
            if open == nil {
                let event = ClockLossEvent(
                    deviceId: deviceId,
                    detectedAt: wall,
                    strapNewestCorrupt: newest,
                    strapOldestCorrupt: oldest,
                    lastGoodFrontier: frontier,
                    reason: reason)
                if let id = try? await whoopStore?.insertClockLossEvent(event) {
                    log("Clock lost: event id=\(id) recorded (frontier=\(frontier.map(String.init) ?? "nil"))")
                }
            }
            let anchor = ClockLossPolicy.anchor(
                strapNewest: newest,
                strapOldest: oldest,
                wallAtDetect: wall,
                lastGoodFrontier: frontier)
            backfiller?.clockLossAnchor = anchor
            startClockLossSalvageThenRepair(reason: reason)
        }
    }

    /// Pause auto offloads and show the charger hold — used when RTC won't latch after salvage/repair.
    private func enterClockHold(reason: String) {
        state.offloadStalled = true
        state.strapNeedsReboot = true
        state.clockLossStatus = OffloadStallPolicy.clockHoldStatus
        log("Clock hold: \(reason) — auto offload paused until DATA_RANGE sane")
    }

    /// One remapped SEND_HISTORICAL attempt, then SET_CLOCK + reboot (even if salvage times out).
    private func startClockLossSalvageThenRepair(reason: String) {
        if !OffloadStallPolicy.shouldStartSalvage(alreadySalvagedThisEpisode: didSalvageThisClockLoss) {
            // Already salvaged this episode — do NOT start another offload storm.
            log("Clock lost: salvage already tried — holding (\(reason))")
            enterClockHold(reason: reason)
            if !scheduleAutoRepairIfNeeded(reason: reason) {
                log("Clock lost: auto-repair on cooldown — charger hold")
            }
            return
        }
        didSalvageThisClockLoss = true
        pendingRepairAfterSalvage = true
        state.offloadStalled = false
        state.consecutiveOffloadTimeouts = 0

        if backfilling {
            log("Clock lost: offload already running — will repair when it ends")
        } else {
            log("Clock lost: starting salvage offload with timestamp remap")
            beginBackfill(forceDespiteStall: true)
        }

        salvageDeadline?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.finishSalvageAndRepair(reason: "salvage timeout")
        }
        salvageDeadline = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .seconds(BLEManager.clockLossSalvageTimeoutSeconds),
            execute: item)
    }

    private func finishSalvageAndRepair(reason: String) {
        guard pendingRepairAfterSalvage else { return }
        pendingRepairAfterSalvage = false
        salvageDeadline?.cancel()
        salvageDeadline = nil
        persistClockLossSalvageStats()
        if backfilling {
            backfiller?.timeoutFired()
            exitBackfilling(reason: "salvage-end")
        }
        log("Clock lost: salvage done (\(reason)) — repairing RTC")
        state.clockLossStatus = "RTC perdido — reparando reloj…"
        if !scheduleAutoRepairIfNeeded(reason: reason) {
            enterClockHold(reason: "auto-repair on cooldown after salvage")
        }
    }

    private func persistClockLossSalvageStats() {
        guard let bf = backfiller else { return }
        let remapped = bf.remappedRowsThisSession
        let dropped = bf.droppedRowsThisSession
        guard remapped > 0 || dropped > 0 else { return }
        log("Clock lost: salvage stats remapped=\(remapped) dropped=\(dropped)")
        Task { @MainActor in
            try? await whoopStore?.addClockLossSalvageStats(
                deviceId: deviceId, remapped: remapped, dropped: dropped)
            bf.resetSalvageStats()
        }
    }

    private func markClockLossRecoveredIfNeeded(wall: Int) {
        let inClockEpisode = rtcKnownCorrupt
            || state.clockLossStatus != nil
            || state.lastClockLossDetectedAt != nil
        guard inClockEpisode else { return }

        let heldForClock = state.clockLossStatus != nil
        rtcKnownCorrupt = false
        backfiller?.clockLossAnchor = nil
        didSalvageThisClockLoss = false
        pendingRepairAfterSalvage = false
        salvageDeadline?.cancel()
        salvageDeadline = nil
        state.clockLossStatus = nil
        // Only lift stall when we were holding for RTC — leave a non-RTC stall alone.
        if heldForClock {
            state.offloadStalled = false
            state.consecutiveOffloadTimeouts = 0
            state.strapNeedsReboot = false
        }
        log("Clock lost: recovered — DATA_RANGE sane at wall=\(wall)")
        Task { @MainActor in
            try? await whoopStore?.markClockLossRecovered(deviceId: deviceId, recoveredAt: wall)
        }
        // Alarm may have been deferred during the hold — try now that RTC looks sane.
        flushPendingArmIfNeeded()
    }

    /// Incomplete offload streak ⇒ pause auto-sync so the UI stops lying with "Descargando…" for hours.
    /// Counts ALL timeouts (empty OR partial ~60-frame dribbles). HISTORY_COMPLETE clears the stall
    /// only when RTC is sane — under corrupt RTC it enters charger hold instead of looping.
    /// On stall: auto CLOCK-LOST repair (SET_CLOCK + reboot) when cooldown allows.
    private func noteOffloadOutcome(reason: String, framesSeen: Int) {
        if reason == "HISTORY_COMPLETE" {
            state.consecutiveOffloadTimeouts = 0
            if OffloadStallPolicy.shouldClearStallOnHistoryComplete(rtcKnownCorrupt: rtcKnownCorrupt) {
                if state.offloadStalled {
                    state.offloadStalled = false
                    log("Backfill: stall cleared — HISTORY_COMPLETE")
                }
            } else {
                enterClockHold(reason: "HISTORY_COMPLETE while RTC corrupt frames=\(framesSeen)")
                if OffloadStallPolicy.isVacuousHistoryComplete(frames: framesSeen,
                                                              rtcKnownCorrupt: true) {
                    log("Backfill: vacuous HISTORY_COMPLETE under corrupt RTC — not caught up")
                }
            }
            return
        }
        guard reason == "timeout" else { return }
        // Salvage offload owns the next repair step — don't double-trigger stall repair.
        if pendingRepairAfterSalvage {
            log("Backfill: salvage timeout frames=\(framesSeen) — deferring to salvage→repair")
            return
        }
        state.consecutiveOffloadTimeouts += 1
        log("Backfill: incomplete timeout \(state.consecutiveOffloadTimeouts)/\(BLEManager.offloadStallAfterTimeouts) frames=\(framesSeen)")
        if state.consecutiveOffloadTimeouts >= BLEManager.offloadStallAfterTimeouts {
            state.offloadStalled = true
            state.strapNeedsReboot = true
            log("Backfill: STALLED — pausing auto-sync")
            if rtcKnownCorrupt {
                state.clockLossStatus = OffloadStallPolicy.clockHoldStatus
            }
            if !scheduleAutoRepairIfNeeded(reason: "offload_stall") {
                log("Backfill: STALLED — auto-repair on cooldown; put strap on charger")
            }
        }
    }

    /// Kick SET_CLOCK + strap reboot when the RTC looks lost. Returns true if a repair was started.
    @discardableResult
    private func scheduleAutoRepairIfNeeded(reason: String) -> Bool {
        if didAutoRepairThisConnection {
            log("Auto-repair: skip (\(reason)) — already tried this connection")
            return false
        }
        let now = Date().timeIntervalSince1970
        if let last = UserDefaults.standard.object(forKey: BLEManager.autoRepairLastAtKey) as? Double,
           now - last < BLEManager.autoRepairCooldownSeconds {
            let left = Int(BLEManager.autoRepairCooldownSeconds - (now - last))
            log("Auto-repair: skip (\(reason)) — cooldown \(left)s left")
            return false
        }
        didAutoRepairThisConnection = true
        UserDefaults.standard.set(now, forKey: BLEManager.autoRepairLastAtKey)
        state.offloadStalled = true
        state.strapNeedsReboot = true
        log("Auto-repair: starting CLOCK-LOST recovery (\(reason))")
        repairStrapClock(automatic: true)
        return true
    }

    /// After an offload, judge liveness: stuck = strap reports records newer than our frontier AND our
    /// frontier (max persisted HR ts) hasn't advanced for the detector window. Off-wrist / caught up
    /// (strap not ahead) is NOT stuck. On stuck: attempt recovery (defensive EXIT + SET_CLOCK) and raise
    /// the surface. Best-effort; reads the frontier via the Collector (which owns the concrete store).
    private func checkStrapLiveness() {
        let strapNewest = strapNewestTs
        Task { @MainActor in
            // Frontier = newest HR ts persisted by the HISTORICAL offload (cursor advanced per
            // chunk by the Backfiller), NOT the store-wide max HR ts: live realtime samples
            // advance the store-wide max continuously while connected, which kept the detector
            // reading "progressing" through a 3-day-dead offload. Seeded once from the store-wide
            // max so there's a baseline before the first post-fix chunk lands; after that only
            // real historical chunks move it.
            var front = (try? await whoopStore?.cursor("hist_hr_frontier")) ?? nil
            if front == nil, let seed = await collector?.latestHRSampleTs() {
                try? await whoopStore?.setCursor("hist_hr_frontier", seed)
                front = seed
            }
            let now = Date().timeIntervalSince1970
            let stuck = stuckDetector.observe(strapNewestTs: strapNewest,
                                              ourFrontierTs: front,
                                              now: now)
            state.strapNeedsReboot = stuck
            if stuck {
                if state.offloadStalled {
                    log("Watchdog: behind + frontier frozen — already stalled; skip SET_CLOCK spam")
                    return
                }
                log("Watchdog: behind + frontier frozen — recovery (exit high-freq + SET_CLOCK)")
                send(.exitHighFreqSync, payload: [0x00])
                send(.setClock, payload: BLEManager.setClockPayload())
            }
        }
    }

    /// Fire-and-forget drain: pushes any pending rows to the server.
    /// No-op when uploader is nil (placeholder secrets / unconfigured).
    private func uploadOpportunistically() {
        guard let uploader else { return }
        Task { await uploader.drain() }
    }

    /// Fire-and-forget server pull: GET new decoded streams + derived metrics since the read
    /// highwater and upsert locally (History = union(phone-collected, server-computed)). Best-effort
    /// — a pull failure never affects the BLE connection. No-op when serverSync is nil (unconfigured).
    private func pullFromServer() {
        guard let serverSync else { return }
        Task { await serverSync.pull() }
    }

    /// Attempt a once-per-launch cloud restore if the local store is empty (fresh reinstall). If
    /// the store is non-empty `restoreIfEmpty()` returns false immediately (< 1ms). Best-effort —
    /// a failure never affects the BLE connection. The `didAttemptRestore` flag prevents re-running
    /// on subsequent reconnects within the same process lifetime; the emptiness check in
    /// `restoreIfEmpty()` itself makes this doubly safe.
    private func restoreFromServerIfNeeded() {
        guard !didAttemptRestore, let serverSync else { return }
        didAttemptRestore = true
        Task { await serverSync.restoreIfEmpty() }
    }

    /// Start (or restart) the periodic upload timer so the server stays current during a long
    /// connected session. Idempotent drains (highwater-gated) make repeated firing safe.
    private func startUploadTimer() {
        uploadTimer?.cancel()
        guard uploader != nil else { return }
        let interval = BLEManager.uploadIntervalSeconds
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + .seconds(interval), repeating: .seconds(interval))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.uploadOpportunistically()
            // Keep the local union current with server-computed metrics — but never while an offload
            // is in flight (the pull would starve the Backfiller's insert→ack on the shared actor).
            if !self.backfilling { self.pullFromServer() }
        }
        t.resume()
        uploadTimer = t
    }

    /// Pure decision: should the periodic timer kick off another historical offload? Only when
    /// connected + bonded and NOT already mid-backfill. Extracted so the gate is unit-testable
    /// without a CoreBluetooth seam. Note this intentionally does NOT consult `backfillStarted`
    /// (that flag guards the once-per-connect INITIAL kick); the periodic re-trigger is separate.
    static func shouldRunPeriodicBackfill(connected: Bool, bonded: Bool, backfilling: Bool) -> Bool {
        connected && bonded && !backfilling
    }

    /// Start (or restart) the periodic backfill timer. Each tick re-runs the type-47 historical
    /// offload while connected+bonded and not already backfilling — the primary metric sync.
    private func startBackfillTimer() {
        backfillTimer?.cancel()
        let interval = BLEManager.backfillIntervalSeconds
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + .seconds(interval), repeating: .seconds(interval))
        t.setEventHandler { [weak self] in self?.triggerPeriodicBackfill() }
        t.resume()
        backfillTimer = t
    }

    /// The single gated entry point for every historical-offload kick. Applies the connection/state
    /// gate AND the BackfillPolicy rate-limiter for the trigger. On a go: records the attempt time
    /// (persisted) and starts the offload.
    func requestSync(_ trigger: BackfillTrigger) {
        guard BLEManager.shouldRunPeriodicBackfill(
            connected: state.connected, bonded: state.bonded, backfilling: backfilling) else { return }
        // Manual sync always gets one more try; auto triggers pause while stalled so we don't
        // hammer SEND_HISTORICAL for hours with a dead RTC / silent history stream.
        if state.offloadStalled, trigger != .manual {
            log("Backfill: \(trigger) skipped (stalled — use Sync now or charger reboot)")
            return
        }
        if trigger == .manual, state.offloadStalled {
            state.offloadStalled = false
            state.consecutiveOffloadTimeouts = 0
            log("Backfill: manual sync clearing stall for one attempt")
        }
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.object(forKey: BLEManager.backfillLastAtKey) as? Double
        guard BackfillPolicy.shouldRun(trigger: trigger, now: now, lastBackfillAt: last) else {
            log("Backfill: \(trigger) skipped (rate-limited; last \(last.map { Int(now - $0) } ?? -1)s ago)")
            return
        }
        UserDefaults.standard.set(now, forKey: BLEManager.backfillLastAtKey)
        beginBackfill()
    }

    /// Periodic-timer callback: routes through the rate-limited requestSync entry point.
    private func triggerPeriodicBackfill() {
        requestSync(.periodic)
    }

    // MARK: Helpers
    private static let logTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    private func log(_ s: String) {
        let line = "[\(timestamp())] \(s)"
        state.append(log: line)
        print("BLE: \(s)")
        // Mirror to Documents/ble-console.log so the log survives the 30-line UI buffer and can be
        // pulled from the Mac (`devicectl device copy files --domain-type appDataContainer`).
        BLEManager.appendToLogFile(line)
    }

    private static let logFileURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ble-console.log")

    private static func appendToLogFile(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let size = (try? FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size]) as? Int,
           size > 2_000_000 {
            try? FileManager.default.removeItem(at: logFileURL)   // crude 2 MB cap: start over
        }
        if let h = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: logFileURL)
        }
    }
    private func timestamp() -> String {
        BLEManager.logTimeFormatter.string(from: Date())
    }
    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Alarm API (M6 — additive; does NOT touch connect/offload/sync flows)

    /// Arm the strap's firmware alarm for `date` (UTC).
    ///
    /// Sequence: DISABLE → SET_CLOCK (wait for latch) → SET_ALARM_TIME → GET_ALARM_TIME verify.
    /// Deferred while a historical offload is running — alarm commands are unreliable mid-sync.
    /// The strap will buzz at `date` even if the app is force-quit (event STRAP_DRIVEN_ALARM_EXECUTED=57).
    @discardableResult
    func armStrapAlarm(at date: Date) -> Bool {
        guard isStrapReadyForCommands else {
            log("Alarm: arm skipped — strap not ready (connected=\(state.connected) handshake=\(connectHandshakeDone))")
            return false
        }
        // Alarm arming blasts SET_CLOCK/SET_ALARM and times out under CLOCK-LOST, crowding out
        // the real repair path. Hold the pending target; restore after DATA_RANGE is sane.
        if rtcKnownCorrupt || state.clockLossStatus != nil {
            log("Alarm: arm deferred — RTC corrupt / clock hold active")
            let epochSec = UInt32(date.timeIntervalSince1970)
            pendingArm = PendingArm(targetEpoch: epochSec, fireDate: date, attempt: 0)
            state.firmwareAlarmVerified = false
            return false
        }
        guard date.timeIntervalSinceNow > 5 else {
            log("Alarm: arm skipped — fire time too soon")
            return false
        }
        let epochSec = UInt32(date.timeIntervalSince1970)
        pendingArm = PendingArm(targetEpoch: epochSec, fireDate: date, attempt: 0)
        state.firmwareAlarmVerified = false
        if backfilling {
            log("Alarm: defer arm until backfill completes (target \(date))")
            return true
        }
        startArmSequence()
        return true
    }

    /// Disarm the currently-armed firmware alarm.
    @discardableResult
    func disableStrapAlarm() -> Bool {
        cancelArmSequence()
        pendingArm = nil
        state.firmwareAlarmEpoch = nil
        state.firmwareAlarmVerified = false
        guard isStrapReadyForCommands else {
            log("Alarm: disarm skipped — strap not ready")
            return false
        }
        send(.disableAlarm, payload: [0x01], writeType: .withResponse)
        log("Alarm: disarmed")
        return true
    }

    /// Request the currently-armed alarm time from the strap.
    func getStrapAlarm() {
        send(.getAlarmTime, payload: [0x01], writeType: .withResponse)
        log("Alarm: requested current alarm time")
    }

    /// Fire an immediate alarm buzz on the strap for testing.
    func testAlarmBuzz() {
        guard isStrapReadyForCommands else {
            log("Alarm: test buzz skipped — strap not ready")
            return
        }
        send(.runHapticsPattern, payload: [2, 3, 0, 0, 0], writeType: .withResponse)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.send(.runAlarm, payload: [0x01], writeType: .withResponse)
        }
        log("Alarm: test buzz fired (patternId=2, runAlarm)")
    }

    // MARK: Firmware alarm state machine (private)

    private func flushPendingArmIfNeeded() {
        guard pendingArm != nil, !backfilling, armPhase == .idle else { return }
        if rtcKnownCorrupt || state.clockLossStatus != nil {
            log("Alarm: flush deferred — RTC corrupt / clock hold active")
            return
        }
        startArmSequence()
    }

    private func startArmSequence() {
        guard var pending = pendingArm else { return }
        if rtcKnownCorrupt || state.clockLossStatus != nil {
            log("Alarm: arm sequence blocked — RTC corrupt / clock hold active")
            return
        }
        cancelArmStepTimer()
        pending.attempt += 1
        pendingArm = pending
        armPhase = .disabling
        log("Alarm: arm sequence attempt \(pending.attempt)/\(Self.maxArmAttempts) for \(pending.fireDate)")
        send(.disableAlarm, payload: [0x01], writeType: .withResponse)
        scheduleArmStep(after: 0.6) { [weak self] in self?.advanceArmAfterDisable() }
    }

    private func advanceArmAfterDisable() {
        guard pendingArm != nil, armPhase == .disabling else { return }
        cancelArmStepTimer()
        armPhase = .settingClock
        send(.setClock, payload: BLEManager.setClockPayload(), writeType: .withResponse)
        scheduleArmStep(after: 2.5) { [weak self] in self?.retryArmOrFail("SET_CLOCK timeout") }
    }

    private func advanceArmAfterClockSettle() {
        guard let pending = pendingArm, armPhase == .clockSettling else { return }
        cancelArmStepTimer()
        armPhase = .settingAlarm(pending.targetEpoch)
        send(.setAlarmTime, payload: WhoopCommand.setAlarmPayload(epochSec: pending.targetEpoch),
             writeType: .withResponse)
        scheduleArmStep(after: 2.5) { [weak self] in self?.retryArmOrFail("SET_ALARM timeout") }
    }

    private func advanceArmToVerify() {
        guard let pending = pendingArm else { return }
        cancelArmStepTimer()
        armPhase = .verifying(pending.targetEpoch)
        getStrapAlarm()
        scheduleArmStep(after: 2.5) { [weak self] in self?.retryArmOrFail("GET_ALARM verify timeout") }
    }

    private func confirmArmSuccess(epoch: UInt32) {
        guard let pending = pendingArm, epoch == pending.targetEpoch else { return }
        let fireDate = pending.fireDate
        cancelArmStepTimer()
        armPhase = .idle
        pendingArm = nil
        state.firmwareAlarmEpoch = epoch
        state.firmwareAlarmVerified = true
        log("Alarm: firmware verified on strap (epoch \(epoch))")
        onFirmwareAlarmResult?(fireDate, true)
    }

    private func failArm(_ reason: String) {
        cancelArmStepTimer()
        armPhase = .idle
        let fireDate = pendingArm?.fireDate
        pendingArm = nil
        state.firmwareAlarmVerified = false
        log("Alarm: firmware arm failed — \(reason)")
        if let fireDate { onFirmwareAlarmResult?(fireDate, false) }
    }

    private func retryArmOrFail(_ reason: String) {
        guard let pending = pendingArm else { return }
        if pending.attempt >= Self.maxArmAttempts {
            failArm(reason)
            return
        }
        log("Alarm: retrying (\(reason))")
        startArmSequence()
    }

    private func cancelArmSequence() {
        cancelArmStepTimer()
        armPhase = .idle
    }

    private func scheduleArmStep(after seconds: TimeInterval, block: @escaping () -> Void) {
        cancelArmStepTimer()
        let item = DispatchWorkItem(block: block)
        armStepTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func cancelArmStepTimer() {
        armStepTimer?.cancel()
        armStepTimer = nil
    }

    private func handleFirmwareAlarmEvent(_ name: String) {
        log("Alarm: strap event \(name)")
        if name.hasPrefix("STRAP_DRIVEN_ALARM_SET"), let epoch = pendingArm?.targetEpoch {
            confirmArmSuccess(epoch: epoch)
        }
        if name.hasPrefix("STRAP_DRIVEN_ALARM_EXECUTED") {
            log("Alarm: strap firmware alarm fired")
        }
        if name.hasPrefix("STRAP_DRIVEN_ALARM_DISABLED") {
            state.firmwareAlarmEpoch = nil
            state.firmwareAlarmVerified = false
        }
    }

    /// Route COMMAND_RESPONSE frames for the alarm arm sequence.
    private func handleAlarmCommandResponse(_ frame: [UInt8]) {
        guard frame.count > 10, frame[4] == 36 else { return } // COMMAND_RESPONSE
        let respCmd = frame[6]
        let pay = Array(frame[7..<(frame.count - 4)])

        switch (armPhase, respCmd) {
        case (.disabling, WhoopCommand.disableAlarm.rawValue):
            advanceArmAfterDisable()
        case (.settingClock, WhoopCommand.setClock.rawValue):
            guard AlarmResponseParser.isOk(pay) else {
                retryArmOrFail("SET_CLOCK rejected")
                return
            }
            cancelArmStepTimer()
            armPhase = .clockSettling
            scheduleArmStep(after: 1.5) { [weak self] in self?.advanceArmAfterClockSettle() }
        case (.settingAlarm(let target), WhoopCommand.setAlarmTime.rawValue):
            guard AlarmResponseParser.isOk(pay) else {
                retryArmOrFail("SET_ALARM rejected")
                return
            }
            if let echoed = AlarmResponseParser.epoch(from: pay), echoed == target {
                confirmArmSuccess(epoch: target)
            } else {
                advanceArmToVerify()
            }
        case (.verifying(let target), WhoopCommand.getAlarmTime.rawValue):
            if let read = AlarmResponseParser.epoch(from: pay), read == target {
                confirmArmSuccess(epoch: target)
            } else {
                retryArmOrFail("GET_ALARM mismatch (got \(AlarmResponseParser.epoch(from: pay) ?? 0), want \(target))")
            }
        default:
            break
        }

        if armPhase == .idle, respCmd == WhoopCommand.getAlarmTime.rawValue,
           let read = AlarmResponseParser.epoch(from: pay), read > 0 {
            state.firmwareAlarmEpoch = read
        }
    }

    /// Parse a standard BLE Heart Rate Measurement (0x2A37) via the pure StandardHeartRate parser.
    private func parseStandardHR(_ data: [UInt8]) {
        guard let m = StandardHeartRate.parse(data) else { return }
        // R-R: the standard profile is the RELIABLE source (the custom REALTIME_DATA stream
        // usually reports rr_count=0), so always surface intervals when present.
        if !m.rr.isEmpty { state.rr = m.rr }
        // HR: prefer the custom stream once bonded; use 0x2A37 HR as a pre-bond fallback.
        if state.heartRate == nil || !state.bonded { state.heartRate = m.hr }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("Central state: \(central.state.rawValue) (5 = poweredOn)")
        guard central.state == .poweredOn else { return }
        // Bootstrap the async store once on first poweredOn (idempotent if already set).
        Task { @MainActor in await bootstrapStore() }
        if let p = restoredPeripheral {
            log("poweredOn with restored peripheral — reconnecting \(p.identifier)")
            if p.state != .connected {
                central.connect(p, options: nil)
            } else {
                p.discoverServices([
                    BLEManager.customService, BLEManager.heartRateService, BLEManager.batteryService,
                ])
            }
        } else {
            connect()
        }
    }

    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any],
                               rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "unknown"
        log("Discovered \(name) (rssi \(RSSI)) — connecting")
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        restoredPeripheral = nil
        state.connected = true
        state.repairStatus = nil
        // Only clear stall after an intentional repair reboot — NOT on every BLE flap. Clearing on
        // every reconnect erased the 3-timeout counter and restarted the offload loop forever.
        if pendingRepairReconnect {
            pendingRepairReconnect = false
            state.offloadStalled = false
            state.consecutiveOffloadTimeouts = 0
            // Keep didSalvageThisClockLoss / rtcKnownCorrupt for this episode. Resetting salvage
            // here re-armed a second salvage→timeout→stall loop after every soft repair.
            log("Connect: post-repair reconnect — one offload attempt allowed (episode salvage kept)")
        }
        // Allow one auto-repair per connection; cooldown still caps frequency across reconnects.
        didAutoRepairThisConnection = false
        log("Connected — discovering services")
        peripheral.discoverServices([
            BLEManager.customService, BLEManager.heartRateService, BLEManager.batteryService,
        ])
    }

    public func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        Task { @MainActor in await collector?.flush() }
        state.connected = false
        didBond = false
        clockRequested = false
        clockRef = nil
        collector?.clockRef = nil
        backfiller?.clockRef = nil
        connectHandshakeDone = false
        // Reset backfill state so the next connect starts a fresh offload.
        backfillStarted = false
        backfilling = false
        state.isOffloading = false
        backfillTimeout?.cancel()
        backfillTimeout = nil
        backfillFrameQueue.removeAll()
        backfillDraining = false
        uploadTimer?.cancel()
        uploadTimer = nil
        backfillTimer?.cancel()
        backfillTimer = nil
        if !intentionalDisconnect {
            log("Disconnected\(error.map { " — \($0.localizedDescription)" } ?? ""); rescanning in 3s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, !self.intentionalDisconnect else { return }
                self.connect()
            }
        } else {
            log("Disconnected (intentional)")
        }
    }

    public func centralManager(_ central: CBCentralManager,
                               didFailToConnect peripheral: CBPeripheral,
                               error: Error?) {
        log("Failed to connect\(error.map { " — \($0.localizedDescription)" } ?? "")")
    }

    /// State restoration entry point (M3 background collection).
    /// Stores the restored peripheral and — if already connected — immediately
    /// re-discovers services so `cmdCharacteristic` is re-acquired and
    /// notifications are re-routed without user interaction.
    public func centralManager(_ central: CBCentralManager,
                               willRestoreState dict: [String: Any]) {
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let p = peripherals.first else {
            log("Restore: no peripherals in state dict")
            return
        }
        self.peripheral = p
        self.restoredPeripheral = p
        p.delegate = self
        // Collection only runs post-bond, so a restored link was already bonded;
        // seed those flags now. `didWriteValueFor` won't re-fire on its own.
        state.bonded = true
        didBond = true
        // clockRef is nil in the fresh process after restore, so we must re-request it.
        // Reset the flag so the post-restore didWriteValueFor issues exactly one getClock.
        clockRequested = false
        // Ensure the store is ready before restored BLE data arrives (idempotent; no-op if already built).
        Task { @MainActor in await bootstrapStore() }
        if p.state == .connected {
            state.connected = true
            log("Restored CONNECTED peripheral \(p.identifier) — re-discovering services")
            p.discoverServices([
                BLEManager.customService, BLEManager.heartRateService, BLEManager.batteryService,
            ])
        } else {
            state.connected = false
            log("Restored DISCONNECTED peripheral \(p.identifier) — reconnect on poweredOn")
            if central.state == .poweredOn { central.connect(p, options: nil) }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for s in services {
            switch s.uuid {
            case BLEManager.customService:
                peripheral.discoverCharacteristics(
                    [BLEManager.cmdWriteChar, BLEManager.cmdNotifyChar,
                     BLEManager.eventNotifyChar, BLEManager.dataNotifyChar], for: s)
            case BLEManager.heartRateService:
                peripheral.discoverCharacteristics([BLEManager.heartRateChar], for: s)
            case BLEManager.batteryService:
                peripheral.discoverCharacteristics([BLEManager.batteryChar], for: s)
            default: break
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars {
            switch c.uuid {
            case BLEManager.cmdWriteChar:
                cmdCharacteristic = c
                // THE BONDING TRICK: one confirmed write triggers just-works bonding.
                // GET_BATTERY_LEVEL is benign and what the Mac prototype uses.
                seq = seq &+ 1
                let bondFrame = WhoopCommand.getBatteryLevel.frame(seq: seq, payload: [0x00])
                log("Bonding: confirmed write GET_BATTERY_LEVEL to 61080002")
                peripheral.writeValue(Data(bondFrame), for: c, type: .withResponse)
            case BLEManager.cmdNotifyChar,
                 BLEManager.eventNotifyChar,
                 BLEManager.dataNotifyChar,
                 BLEManager.heartRateChar,
                 BLEManager.batteryChar:
                peripheral.setNotifyValue(true, for: c)
                log("Subscribed \(c.uuid)")
            default: break
            }
        }
    }

    /// Confirmed-write completion = bonding succeeded (no error).
    public func peripheral(_ peripheral: CBPeripheral,
                           didWriteValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        if let error = error {
            log("Confirmed write failed: \(error.localizedDescription)")
            return
        }
        if !didBond {
            didBond = true
            state.bonded = true
            log("BONDED (confirmed write acknowledged) — custom channels should now flow")
        }
        // Run the connect handshake EXACTLY ONCE per connection. didWriteValueFor re-fires on EVERY
        // .withResponse write — the bond write, every SEND_HISTORICAL, every HISTORY_END ack. Without
        // this guard those re-entries re-sent hello/SET_CLOCK at the strap *during* the offload and
        // stopped it from streaming type-47. This was THE iOS-side root cause: the Mac prototype pulls
        // type-47 fine because it runs the sequence once on a stable connection; the app stormed it.
        guard !connectHandshakeDone else { return }
        connectHandshakeDone = true
        backfillStarted = true

        // WHOOP-faithful connect lifecycle: hello → set RTC,
        // then offload. Hello is NOT strictly required to serve — verified on this strap via the Mac
        // ground-truth test: plain SEND_HISTORICAL_DATA serves type-47 with no hello and no high-freq-sync
        // (PHASE A = 50 records; PHASE B high-freq = 0). We still exchange hello to mirror WHOOP exactly.
        send(.getHelloHarvard)
        send(.getAdvertisingNameHarvard)
        send(.setClock, payload: BLEManager.setClockPayload())
        if clockRef == nil && !clockRequested {
            clockRequested = true
            send(.getClock, payload: [])   // the strap expects GET_CLOCK with an EMPTY payload;
                                           // the app's old default [0x00] is a wrong length the strap ignores.
                                           // (Offload no longer depends on this — Backfiller falls back to an
                                           // identity clockRef — but a real correlation helps realtime decode.)
        }
        send(.sendR10R11Realtime, payload: [0x00])   // stop the type-43 realtime flood (BLE airtime/battery)
        send(.toggleRealtimeHR, payload: [0x01])     // keep type-40 HR flowing while connected (not only on Device tab)
        send(.getDataRange)                          // refresh the strap's stored range for the watchdog
        // Plain offload (no high-freq-sync), rate-limited (first connect always runs; reconnect-flaps are
        // throttled by BackfillPolicy). Deferred ~1.5s so SET_CLOCK/GET_DATA_RANGE round-trip first and
        // SEND_HISTORICAL runs on a settled link, like the paced Mac prototype. beginBackfill is itself
        // gated on connectHandshakeDone so a racing foreground/restore trigger can't fire it early.
        // Under CLOCK-LOST, skip auto offload — vacuous HISTORY_COMPLETE just burns airtime while the
        // alarm path was also fighting SET_CLOCK. Wait for a sane DATA_RANGE (or manual Sync).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            if self.rtcKnownCorrupt || self.state.clockLossStatus != nil {
                self.log("Backfill: connect skipped — RTC still corrupt (await sane DATA_RANGE)")
                self.enterClockHold(reason: "post-connect RTC still corrupt")
                return
            }
            self.requestSync(.connect)
        }
        Task { await self.recoverStrandedUploadsIfNeeded() }
        uploadOpportunistically()
        // NOTE: the server pull + cloud-restore are deliberately NOT kicked here. They share the
        // WhoopStore actor with the historical offload, and a large first-run pull would starve the
        // Backfiller's per-chunk insert→ack. They run from exitBackfilling() once the offload drains.
        startUploadTimer()     // keep the server current during the live session
        startBackfillTimer()   // re-offload the type-47 store every backfillIntervalSeconds
        onStrapReady?()
        // CLOCK-LOST recovery on demand (`-repairStrap` launch arg): once per process launch,
        // 2s after the handshake's SET_CLOCK, reboot the strap so the clock latches and biometric
        // logging resumes (see WhoopCommand.rebootStrap). The post-reboot reconnect runs a fresh
        // handshake (SET_CLOCK + GET_DATA_RANGE); a DATA_RANGE response appearing again is the
        // success signal.
        if ProcessInfo.processInfo.arguments.contains("-repairStrap"), !didSendRepairReboot {
            didSendRepairReboot = true
            log("Repair: CLOCK-LOST recovery — SET_CLOCK + reboot in 2s to latch")
            send(.setClock, payload: BLEManager.setClockPayload())
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.send(.rebootStrap, payload: [0x00])
            }
        }
    }

    /// CLOCK-LOST recovery: pulse SET_CLOCK several times, then reboot to latch.
    /// Non-destructive — the strap's data store survives a reboot; the link drops and
    /// re-establishes in seconds.
    ///
    /// Sends the verified 9-byte SET_CLOCK form. The 2026-05-24 recovery that revived this
    /// strap's dead RTC used `[unix u32 LE][5 pad]`; the 8-byte form is silently ignored
    /// on a clock-lost strap. A single SET_CLOCK+2s-reboot often fails to latch on a deep
    /// CLOCK-LOST — pulse 3× with settle, then reboot. Best odds: strap ON the charger.
    /// - Parameter automatic: true when kicked by stall / insane DATA_RANGE (UI copy differs).
    public func repairStrapClock(automatic: Bool = false) {
        let who = automatic ? "auto" : "manual"
        log("Repair: \(who) CLOCK-LOST recovery — abort offload + SET_CLOCK×3 + reboot")
        pendingRepairReconnect = true
        state.repairStatus = automatic
            ? "Reparando reloj — déjala en el cargador…"
            : "Reparando reloj — SET_CLOCK×3 + reboot (mejor en cargador)…"
        state.clockLossStatus = "RTC perdido — reparando (déjala en el cargador)…"

        cancelArmSequence()
        // Don't resume a failing alarm-arm storm across the reboot.
        pendingArm = nil
        if backfilling {
            backfiller?.timeoutFired()
            exitBackfilling(reason: "repair")
        }
        backfillFrameQueue.removeAll()
        backfillDraining = false
        state.offloadStalled = true   // block further SEND_HISTORICAL until reconnect
        send(.toggleRealtimeHR, payload: [0x00])
        send(.exitHighFreqSync, payload: [0x00])

        // Pulse wall time onto the strap several times before reboot — one shot was not latching.
        let pulseCount = 3
        let pulseSpacing: TimeInterval = 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.pulseSetClockThenReboot(remaining: pulseCount, spacing: pulseSpacing)
        }
    }

    private func pulseSetClockThenReboot(remaining: Int, spacing: TimeInterval) {
        guard remaining > 0 else {
            log("Repair: pulsing done — REBOOT_STRAP")
            send(.rebootStrap, payload: [0x00], writeType: .withResponse)
            return
        }
        log("Repair: SET_CLOCK pulse (\(4 - remaining)/3)")
        send(.setClock, payload: BLEManager.setClockPayload(), writeType: .withResponse)
        DispatchQueue.main.asyncAfter(deadline: .now() + spacing) { [weak self] in
            self?.pulseSetClockThenReboot(remaining: remaining - 1, spacing: spacing)
        }
    }

    /// SET_CLOCK(10) payload = `[unix u32 LE][5 zero pad]` (9 bytes).
    /// VERIFIED LIVE on this strap (2026-07-13, `-bleDebug` capture): the 9-byte form gets a
    /// cmd=10 ACK and latches (with a reboot) a lost RTC; the 8-byte `[seconds][subseconds]`
    /// form is silently ignored — no ack, healthy or wedged. (An older comment here claimed the
    /// reverse; it did not survive contact with the hardware.)
    static func setClockPayload(now: UInt32 = UInt32(Date().timeIntervalSince1970)) -> [UInt8] {
        [UInt8(now & 0xFF), UInt8((now >> 8) & 0xFF),
         UInt8((now >> 16) & 0xFF), UInt8((now >> 24) & 0xFF),
         0, 0, 0, 0, 0]
    }

    /// Newest plausible-unix marker in a GET_DATA_RANGE COMMAND_RESPONSE = the strap's newest stored
    /// record. Mirrors re/diagnose_biometrics.py: scan u32 LE words in the response body (data starts at
    /// frame[7], after [type,seq,cmd]), keep those in the unix range, return the max. nil if none.
    static func dataRangeNewestUnix(from frame: [UInt8]) -> Int? {
        guard frame.count > 7 else { return nil }
        let body = Array(frame[7...]); var newest: Int? = nil; var i = 0
        while i + 4 <= body.count {
            let w = Int(body[i]) | Int(body[i+1]) << 8 | Int(body[i+2]) << 16 | Int(body[i+3]) << 24
            if w >= 1_700_000_000 && w <= 1_900_000_000 { newest = max(newest ?? 0, w) }
            i += 4
        }
        return newest
    }

    /// Oldest plausible-unix marker in a GET_DATA_RANGE response = the strap's OLDEST stored record.
    /// Same scan as `dataRangeNewestUnix` but keeps the min — diagnostic only (used to read how far
    /// back the strap's flash buffer reaches, e.g. to date a second-hand strap's last-active period).
    static func dataRangeOldestUnix(from frame: [UInt8]) -> Int? {
        guard frame.count > 7 else { return nil }
        let body = Array(frame[7...]); var oldest: Int? = nil; var i = 0
        while i + 4 <= body.count {
            let w = Int(body[i]) | Int(body[i+1]) << 8 | Int(body[i+2]) << 16 | Int(body[i+3]) << 24
            if w >= 1_700_000_000 && w <= 1_900_000_000 { oldest = min(oldest ?? Int.max, w) }
            i += 4
        }
        return oldest
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)

        switch characteristic.uuid {
        case BLEManager.heartRateChar:
            parseStandardHR(bytes)
        case BLEManager.batteryChar:
            if let pct = bytes.first { state.setBattery(Double(pct)) } // 0x2A19 = percent
        case BLEManager.dataNotifyChar,
             BLEManager.cmdNotifyChar,
             BLEManager.eventNotifyChar:
            // Reassemble (no-op for already-complete frames) then route each complete frame.
            for frame in reassembler.feed(bytes) {
                // `-bleDebug`: dump every COMMAND_RESPONSE frame raw. The parsed paths only log
                // when values look plausible (e.g. DATA_RANGE with a sane unix), so a strap
                // answering with a lost/garbage RTC is indistinguishable from silence without this.
                if bleDebug, frame.count > 6, frame[4] == 36 {
                    log("RX cmd-resp cmd=\(frame[6]) len=\(frame.count) \(hex(Array(frame.prefix(40))))")
                }
                if frame.count > 4, frame[4] == 36 { handleAlarmCommandResponse(frame) }
                router.handle(frame: frame)                       // UI (always)
                if frame.count > 6, frame[6] == WhoopCommand.getDataRange.rawValue,
                   let newest = BLEManager.dataRangeNewestUnix(from: frame) {
                    let wall = Int(Date().timeIntervalSince1970)
                    // Diagnostic: log the full stored-history window the strap reports.
                    let oldest = BLEManager.dataRangeOldestUnix(from: frame)
                    let fmt = ISO8601DateFormatter()
                    let oldestStr = oldest.map { fmt.string(from: Date(timeIntervalSince1970: TimeInterval($0))) } ?? "n/a"
                    let newestStr = fmt.string(from: Date(timeIntervalSince1970: TimeInterval(newest)))
                    log("DATA_RANGE strap window: oldest=\(oldestStr) newest=\(newestStr)")
                    // Future markers (2029/2030) ⇒ CLOCK-LOST. Salvage remapped historical rows
                    // first (type-47 absolute RTC), then SET_CLOCK + reboot to stop the bleeding.
                    if ClockPolicy.isFutureCorrupt(strapNewest: newest, wallNow: wall) {
                        strapNewestTs = nil
                        rtcKnownCorrupt = true
                        handleClockLost(newest: newest, oldest: oldest, wall: wall,
                                        reason: "future_data_range")
                    } else if ClockPolicy.isSaneWallRelative(newest, wallNow: wall) {
                        strapNewestTs = newest
                        markClockLossRecoveredIfNeeded(wall: wall)
                    } else {
                        // Absurdly old — ignore for watchdog, don't auto-reboot (may be idle strap).
                        strapNewestTs = nil
                        log("DATA_RANGE newest too old vs wall — ignoring for liveness")
                    }
                }
                // Clock correlation runs in both live and backfill modes. Once established it
                // unblocks both the Collector (live path) and the Backfiller (chunk decoding).
                if clockRef == nil {
                    let parsed = parseFrame(frame)
                    if let ref = ClockCorrelation.clockRef(from: parsed, wall: Int(Date().timeIntervalSince1970)) {
                        clockRef = ref
                        collector?.clockRef = ref                  // unblocks buffered persistence
                        backfiller?.clockRef = ref                 // unblocks historical chunk decode
                        log("Clock correlated: device=\(ref.device) wall=\(ref.wall)")
                        // Conditional SET_CLOCK (mirrors WHOOP): only when the strap RTC has drifted /
                        // is frozen — not blindly every connect. Offload doesn't depend on this (it uses
                        // clockRef for decoding); SET_CLOCK only keeps FUTURE logging timestamps sane.
                        if ClockPolicy.shouldSetClock(deviceClock: ref.device, wallNow: ref.wall) {
                            log("Clock drift detected — issuing SET_CLOCK")
                            send(.setClock, payload: BLEManager.setClockPayload())
                        }
                    }
                }
                if backfilling {
                    // Historical offload path: route ONLY genuine offload frames (47/48/49/50)
                    // through the serial drain (preserves START/data/END chunk order) and re-arm the
                    // idle watchdog on them. The live type-40/43 flood (esp. the ~2/s, ~1.9 KB type-43
                    // raw) is IGNORED by extractHistoricalStreams, so feeding it to the drain only
                    // delays each chunk's insert→trim-ack — the strap then stalls waiting for the ack
                    // and the 20 s watchdog fires (the residual timeout). Drop the flood during offload.
                    if BLEManager.isOffloadFrame(frame) {
                        offloadFramesThisSession += 1
                        armBackfillTimeout()
                        routeBackfillFrame(frame)
                    }
                } else {
                    // Live path (unchanged): synchronous ingest preserves delegate arrival order.
                    collector?.ingest(frame)
                }
            }
        default:
            break
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        if let error = error {
            log("Notify enable failed for \(characteristic.uuid): \(error.localizedDescription)")
        }
    }
}
