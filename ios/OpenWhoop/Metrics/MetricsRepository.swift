import Foundation
import SwiftUI
import WhoopStore

// MARK: - MetricsRepository
//
// View-facing read facade over the local MetricsCache (WhoopStore tables dailyMetric +
// sleepSession). The phone does NO metric computation: all values are server-computed and
// cached locally by ServerSync.pullDerived(). MetricsRepository only reads the cache and
// delegates network refreshes to ServerSync.
//
// LAZY-OPEN DESIGN: The synchronous init() does NOT open the on-disk store (WhoopStore.init
// is async). Instead, ensureOpen() is called at the top of every async method and opens the
// store + builds ServerSync on the first call. This lets AppRoot create the repo synchronously
// (as a @StateObject) and always inject a non-nil env object — eliminating the brief window
// where RootTabView rendered without the env object and would crash any @EnvironmentObject read.

@MainActor
final class MetricsRepository: ObservableObject {
    @Published private(set) var today: DailyMetric?            // most-recent cached daily row
    @Published private(set) var lastNight: CachedSleepSession? // sleep session whose wake is today (local)
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastPRVNSyncError: String?
    @Published private(set) var lastRefreshedAt: Date?
    @Published private(set) var isDemoPreviewActive = false
    @Published private(set) var sleepInsights: SleepInsightsPayload?

    // Injected directly (test path): store + sync are ready immediately; skip ensureOpen.
    private var store: WhoopStore?
    private var serverSync: ServerSync?
    private let settings: ServerConnectionSettings
    /// When set (test injection), ignores settings.effectiveDeviceId.
    private let pinnedDeviceId: String?

    private var deviceId: String {
        if let pinnedDeviceId { return pinnedDeviceId }
        let effective = settings.effectiveDeviceId
        return effective.isEmpty ? "my-whoop" : effective
    }

    // Lazy-open state (app path).
    private var _alreadyOpen = false
    private var _openTask: Task<Void, Never>?

    // MARK: - Synchronous init (app path — store not yet open)

    /// Creates a repository without opening the on-disk store. The store is opened lazily on the
    /// first async call to load()/refresh()/daily()/sleepSessions(). AppRoot uses this init so it
    /// can always provide a non-nil MetricsRepository env object from the very first frame.
    init(deviceId: String = "my-whoop", settings: ServerConnectionSettings? = nil) {
        self.settings = settings ?? ServerConnectionSettings.shared
        self.pinnedDeviceId = nil
        self.store = nil
        self.serverSync = nil
        self._alreadyOpen = false
        self.isDemoPreviewActive = UserDefaults.standard.bool(forKey: DemoDataLoader.activeKey)
        _ = deviceId // legacy; app path uses settings.effectiveDeviceId
    }

    // MARK: - Designated init (test path — store + sync injected)

    /// Designated initializer for tests: store and sync are ready immediately; ensureOpen() is
    /// a no-op. Keeps all existing MetricsRepository tests passing without modification.
    init(store: WhoopStore, serverSync: ServerSync?, deviceId: String, settings: ServerConnectionSettings? = nil) {
        self.store = store
        self.serverSync = serverSync
        self.settings = settings ?? ServerConnectionSettings.shared
        self.pinnedDeviceId = deviceId
        self._alreadyOpen = true   // already wired — no lazy open needed
    }

    // MARK: - Lazy open (app path)

    /// Idempotent: opens the on-disk store and builds ServerSync exactly once.
    /// All async public methods call this first so the first real operation bootstraps the stack.
    ///
    /// Concurrency contract: all callers on @MainActor await the SAME Task so no second caller
    /// can observe store == nil after ensureOpen() returns. The guard+assign block has no await
    /// between check and assign, so it is atomic on the single MainActor executor.
    private func ensureOpen() async {
        // Test path (store injected) or a previously-completed open: nothing to do.
        if _alreadyOpen, store != nil { return }
        // An open is already in flight — await the SAME task so we don't double-open.
        if let openTask = _openTask { await openTask.value; return }
        let task = Task { @MainActor [self] in
            guard let path = try? StorePaths.defaultDatabasePath(),
                  let openedStore = try? await WhoopStore(path: path) else {
                lastError = "Could not open local database"
                // Allow a retry on a future call.
                _openTask = nil
                return
            }
            store = openedStore
            serverSync = settings.uploaderConfig()
                .map { ServerSync(config: $0, store: openedStore, deviceId: deviceId) }
            _alreadyOpen = true
        }
        _openTask = task
        await task.value
    }

    // MARK: - App factory (kept for backward-compat; AppRoot now prefers init())

    /// Opens the shared on-disk store and builds ServerSync from AppConfig.
    /// Returns nil if the store can't be opened (e.g. sandbox unavailable).
    static func makeDefault(deviceId: String = "my-whoop") async -> MetricsRepository? {
        guard let path = try? StorePaths.defaultDatabasePath(),
              let store = try? await WhoopStore(path: path) else { return nil }
        let sync = ServerConnectionSettings.shared.uploaderConfig()
            .map { ServerSync(config: $0, store: store, deviceId: ServerConnectionSettings.shared.effectiveDeviceId) }
        return MetricsRepository(store: store, serverSync: sync, deviceId: ServerConnectionSettings.shared.effectiveDeviceId)
    }

    /// True when a server URL + API key are available (build defaults or user overrides).
    var isServerConfigured: Bool {
        serverSync != nil || settings.isServerConfigured
    }

    /// Rebuild ServerSync after the user changes connection settings in Ajustes.
    func reloadServerConnection() async {
        await ensureOpen()
        guard let store else { return }
        serverSync = settings.uploaderConfig()
            .map { ServerSync(config: $0, store: store, deviceId: deviceId) }
    }

    // MARK: - Load from cache (no network)

    /// Populate `today`/`lastNight` from the local cache. No network call.
    func load() async {
        await ensureOpen()
        guard let store else { return }

        let now = Date()
        let todayKey = MetricsRepository.localDayString(for: now)
        // WHOOP semantics: "last night" on Hoy = the bout that ended this local wake-morning.
        lastNight = await sleepSession(endingOnDay: todayKey)
        today = await dailyMetricForWakeDay(localDay: todayKey, session: lastNight)
    }

    // MARK: - Refresh from server then reload

    /// Pull derived metrics from the server (if configured) then reload from cache.
    /// Uses pullDerived() — NOT the heavy full-stream pull() — to keep the UI refresh fast.
    /// Safe when serverSync == nil (just reloads). Never throws.
    func refresh() async {
        await ensureOpen()
        isRefreshing = true
        lastError = nil
        if !isDemoPreviewActive {
            if serverSync == nil {
                lastError = "Servidor no configurado"
            } else {
                let ok = await serverSync?.pullDerivedWithStatus() ?? false
                if !ok { lastError = "No se pudo sincronizar con el servidor" }
            }
        }
        await load()
        isRefreshing = false
        lastRefreshedAt = Date()

        if !isDemoPreviewActive {
            await maybeAutoSyncPRVNProgram()
            await loadPRVNProgramFromServerIfNeeded()
            await syncSleepCheckIns()
            await syncCoachContext()
            await fetchSleepInsights()
        }

        // Morning recovery notification: fire once per calendar day when recovery is available.
        if let metric = today, let recovery = metric.recovery {
            RecoveryNotifier.notify(recovery: recovery, forDay: metric.day)
        }
    }

    // MARK: - Range reads for Trends/Sleep tabs

    /// Daily metrics for a day range (YYYY-MM-DD bounds, inclusive). Reads straight from cache.
    func daily(fromDay: String, toDay: String) async -> [DailyMetric] {
        await ensureOpen()
        guard let store else { return [] }
        return (try? await store.dailyMetrics(deviceId: deviceId, from: fromDay, to: toDay)) ?? []
    }

    /// Últimos N días calendario locales (incluye hoy), ordenados por día ascendente.
    func dailyLastDays(_ count: Int, endingOn date: Date = Date(), calendar: Calendar = .current) async -> [DailyMetric] {
        let anchor = calendar.startOfDay(for: date)
        guard let from = calendar.date(byAdding: .day, value: -(count - 1), to: anchor) else { return [] }
        return await daily(fromDay: Self.localDayString(for: from, calendar: calendar),
                           toDay: Self.localDayString(for: anchor, calendar: calendar))
    }

    /// Single daily row for a calendar day key (YYYY-MM-DD).
    func dailyMetric(forDay day: String) async -> DailyMetric? {
        await daily(fromDay: day, toDay: day).first
    }

    /// Match the server ``daily`` row for a **local wake-day**. Only pairs a row when we can
    /// tie it to that night's session (UTC wake-day of ``endTs``) or an exact day-key hit —
    /// never steal a neighbour day's row (that duplicated scores across the day picker).
    func dailyMetricForWakeDay(localDay: String, session: CachedSleepSession?) async -> DailyMetric? {
        if let session, Self.localDayString(fromEpoch: session.endTs) == localDay {
            let utcWake = Self.utcDayString(fromEpoch: session.endTs)
            if let row = await dailyMetric(forDay: utcWake), Self.hasSleepMetrics(row) {
                return row
            }
        }
        if let row = await dailyMetric(forDay: localDay), Self.hasSleepMetrics(row) {
            return row
        }
        return nil
    }

    nonisolated private static func hasSleepMetrics(_ row: DailyMetric) -> Bool {
        (row.totalSleepMin ?? 0) > 0
            || (row.efficiency ?? 0) > 0
            || (row.sleepScore ?? 0) > 0
            || row.deepMin != nil
            || row.remMin != nil
            || row.lightMin != nil
    }

    /// Among sessions, keep the longest **main** bout per local wake-day (`endTs`).
    nonisolated static func primarySessionsPerWakeDay(_ sessions: [CachedSleepSession]) -> [CachedSleepSession] {
        let mains = sessions.filter { $0.isMainNight }
        let pool = mains.isEmpty ? sessions.filter { !$0.isNap } : mains
        var byDay: [String: CachedSleepSession] = [:]
        for s in pool {
            let day = localDayString(fromEpoch: s.endTs)
            if let existing = byDay[day] {
                if (s.endTs - s.startTs) > (existing.endTs - existing.startTs) {
                    byDay[day] = s
                }
            } else {
                byDay[day] = s
            }
        }
        return byDay.values.sorted { $0.startTs < $1.startTs }
    }

    private func sessionsEndingOnDay(_ day: String) async -> [CachedSleepSession] {
        await ensureOpen()
        guard let store else { return [] }
        guard let bounds = Self.epochBounds(forDay: day) else { return [] }
        let windowStart = bounds.start - 86_400
        let windowEnd   = bounds.end + 86_400
        let sessions = (try? await store.sleepSessions(deviceId: deviceId,
                                                       from: windowStart,
                                                       to: windowEnd,
                                                       limit: 30)) ?? []
        return sessions.filter { Self.localDayString(fromEpoch: $0.endTs) == day }
    }

    /// Sleep session whose wake (`endTs`) falls on `day` (local calendar `yyyy-MM-dd`).
    func sleepSession(endingOnDay day: String) async -> CachedSleepSession? {
        let onDay = await sessionsEndingOnDay(day)
        let mains = onDay.filter { $0.isMainNight }
        let pool = mains.isEmpty ? onDay.filter { !$0.isNap } : mains
        if pool.isEmpty {
            return onDay.max(by: { ($0.endTs - $0.startTs) < ($1.endTs - $1.startTs) })
        }
        return pool.max(by: { ($0.endTs - $0.startTs) < ($1.endTs - $1.startTs) })
    }

    /// Fallback when local wake-day misses but the server daily row exists (UTC wake-day key).
    private func sleepSession(matchingServerWakeDay serverDay: String, nearLocalDay localDay: String) async -> CachedSleepSession? {
        await ensureOpen()
        guard let store, let anchor = Self.parseLocalDay(localDay) else { return nil }
        let cal = Calendar.current
        guard let fromDate = cal.date(byAdding: .day, value: -1, to: anchor),
              let toDate = cal.date(byAdding: .day, value: 2, to: anchor) else { return nil }
        let from = Int(fromDate.timeIntervalSince1970)
        let to = Int(toDate.timeIntervalSince1970)
        let candidates = (try? await store.sleepSessions(deviceId: deviceId, from: from, to: to, limit: 40)) ?? []
        let pool = candidates.filter {
            !$0.isNap && Self.utcDayString(fromEpoch: $0.endTs) == serverDay
        }
        return pool.max(by: { ($0.endTs - $0.startTs) < ($1.endTs - $1.startTs) })
    }

    /// Siestas / descanso etiquetados como ``nap`` para el día de despertar `day`.
    func naps(endingOnDay day: String) async -> [CachedSleepSession] {
        let onDay = await sessionsEndingOnDay(day)
        return onDay.filter { $0.isNap }.sorted { $0.startTs < $1.startTs }
    }

    /// Local calendar `yyyy-MM-dd` for metric lookups and weekly charts (matches server UTC day labels for CET users).
    nonisolated static func localDayString(for date: Date, calendar: Calendar = .current) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: calendar.startOfDay(for: date))
    }

    nonisolated static func localDayString(fromEpoch epoch: Int, calendar: Calendar = .current) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    /// Parse local `yyyy-MM-dd` back to start-of-day `Date`.
    nonisolated static func parseLocalDay(_ dayKey: String, calendar: Calendar = .current) -> Date? {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: dayKey).map { calendar.startOfDay(for: $0) }
    }

    /// UTC `yyyy-MM-dd` for the instant of local start-of-day (legacy sleep/window keys).
    nonisolated static func utcDayString(for date: Date, calendar: Calendar = .current) -> String {
        dayString(fromEpoch: Int(calendar.startOfDay(for: date).timeIntervalSince1970))
    }

    /// UTC calendar day for an instant — matches server sleep/daily attribution (`end_ts` date).
    nonisolated static func utcDayString(fromEpoch epoch: Int) -> String {
        dayString(fromEpoch: epoch)
    }

    nonisolated private static func dayString(fromEpoch epoch: Int) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    private static func epochBounds(forDay day: String, calendar: Calendar = .current) -> (start: Int, end: Int)? {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: day) else { return nil }
        let start = Int(date.timeIntervalSince1970)
        return (start, start + 86_400 - 1)
    }

    /// Sleep sessions overlapping [from, to] (epoch seconds). Reads straight from cache.
    func sleepSessions(from: Int, to: Int, limit: Int) async -> [CachedSleepSession] {
        await ensureOpen()
        guard let store else { return [] }
        return (try? await store.sleepSessions(deviceId: deviceId, from: from, to: to, limit: limit)) ?? []
    }

    // MARK: - Profile (M0.5)

    /// Best-effort GET /v1/profile. Returns nil when unconfigured or on error.
    func getProfile() async -> Profile? {
        await ensureOpen()
        return await serverSync?.getProfile()
    }

    /// Best-effort POST /v1/profile. Returns true on 2xx, false when unconfigured or on error.
    func putProfile(_ profile: Profile) async -> Bool {
        await ensureOpen()
        return await serverSync?.putProfile(profile) ?? false
    }

    /// Pull recent check-ins from server and merge into local store.
    func syncSleepCheckIns() async {
        await ensureOpen()
        guard let serverSync else { return }
        let cal = Calendar.current
        let to = Date()
        guard let from = cal.date(byAdding: .day, value: -60, to: to) else { return }
        let fromDay = Self.localDayString(for: from, calendar: cal)
        let toDay = Self.localDayString(for: to, calendar: cal)
        if let remote = await serverSync.getSleepCheckIns(from: fromDay, to: toDay) {
            SleepCheckInStore.shared.mergeFromServer(remote)
        }
    }

    /// Push one check-in to server (idempotent upsert). Best-effort.
    func pushSleepCheckIn(_ checkIn: SleepCheckIn) async {
        await ensureOpen()
        _ = await serverSync?.putSleepCheckIn(checkIn)
        await refreshDaily(dayKey: checkIn.dayKey)
    }

    /// Pull one day of daily metrics after check-in updates sleep score on server.
    func refreshDaily(dayKey: String) async {
        await ensureOpen()
        guard let store, let serverSync else { return }
        if let days = await serverSync.fetchDaily(from: dayKey, to: dayKey), !days.isEmpty {
            try? await store.upsertDailyMetrics(days, deviceId: deviceId)
            await load()
        }
    }

    func fetchSleepInsights() async {
        await ensureOpen()
        sleepInsights = await serverSync?.getSleepInsights(days: 60)
    }

    /// Push manual workout day plan to server for coach context. Best-effort.
    func pushDayPlan(dayKey: String, plan: WorkoutDayPlan?) async {
        await ensureOpen()
        guard let serverSync else { return }
        if let plan, plan.hasContent {
            _ = await serverSync.putDayPlan(dayKey: dayKey, plan: plan)
        } else {
            _ = await serverSync.deleteDayPlan(dayKey: dayKey)
        }
    }

    /// Push mobility session completion to server. Best-effort.
    func pushMobilityCompletion(_ entry: MobilityCompletionEntry) async {
        await ensureOpen()
        _ = await serverSync?.putMobilityCompletion(entry)
    }

    /// Pull day plans + mobility completions from server and merge into local stores.
    func syncCoachContext() async {
        await ensureOpen()
        guard let serverSync else { return }
        let cal = Calendar.current
        let to = Date()
        guard let from = cal.date(byAdding: .day, value: -30, to: to) else { return }
        let fromDay = Self.localDayString(for: from, calendar: cal)
        let toDay = Self.localDayString(for: to, calendar: cal)
        if let remotePlans = await serverSync.getDayPlans(from: fromDay, to: toDay) {
            WorkoutDayPlanStore.shared.mergeFromServer(remotePlans)
        }
        if let remoteMobility = await serverSync.getMobilityCompletions(from: fromDay, to: toDay) {
            MobilityCompletionStore.shared.mergeFromServer(remoteMobility)
        }
    }

    /// Fetch training coach report (GET cache, else POST compute). Best-effort.
    func coachReport(forDay dayKey: String, recompute: Bool = false) async -> TrainingDayCoachReport? {
        await ensureOpen()
        guard let serverSync else { return nil }
        if recompute {
            return await serverSync.computeCoachReport(dayKey: dayKey)
        }
        return await serverSync.fetchCoachReport(dayKey: dayKey)
    }

    /// Optional LLM/template narrative for a coach report. Requires toggle in Settings.
    func coachNarrative(forDay dayKey: String) async -> CoachNarrativeResponse? {
        await ensureOpen()
        guard CoachLLMSettings.isEnabled else { return nil }
        return await serverSync?.explainCoachReport(
            dayKey: dayKey,
            includeNote: CoachLLMSettings.includeDayNote
        )
    }

    /// Analiza transcripción de voz en servidor y devuelve sensación estructurada + contraste con pulsera.
    func analyzeSleepCheckIn(transcript: String,
                             dayKey: String,
                             recoveryPct: Double?,
                             sleepEfficiencyPct: Double?) async -> SleepCheckInAnalyzeResult? {
        await ensureOpen()
        return await serverSync?.analyzeSleepCheckIn(
            transcript: transcript,
            dayKey: dayKey,
            recoveryPct: recoveryPct,
            sleepEfficiencyPct: sleepEfficiencyPct
        )
    }

    /// Pull PRVN week from SugarWOD via server credentials. Returns false when unconfigured or on error.
    func syncPRVNProgram(weekStart: Date? = nil) async -> Bool {
        await ensureOpen()
        guard let serverSync else {
            lastPRVNSyncError = "Servidor no configurado. Revisa WHOOP_BASE_URL y WHOOP_API_KEY."
            return false
        }
        let weekKey: String?
        if let weekStart {
            let monday = PRVNProgramStore.monday(containing: weekStart)
            let fmt = DateFormatter()
            fmt.calendar = Calendar.current
            fmt.timeZone = TimeZone(identifier: "UTC")
            fmt.dateFormat = "yyyyMMdd"
            weekKey = fmt.string(from: monday)
        } else {
            weekKey = nil
        }
        let result = await serverSync.syncPRVNProgram(weekYYYYMMDD: weekKey)
        if let payload = result.payload {
            lastPRVNSyncError = nil
            PRVNProgramStore.shared.importFromServer(pasteText: payload.pasteText, weekStartISO: payload.weekStart)
            return true
        }
        lastPRVNSyncError = result.errorMessage
            ?? "No se pudo sincronizar PRVN. Revisa credenciales SugarWOD en el servidor."
        return false
    }

    /// Domingo: sincroniza la semana que empieza el lunes siguiente (una vez por semana).
    func syncPRVNProgramIfSunday() async {
        await ensureOpen()
        await maybeAutoSyncPRVNProgram()
        await loadPRVNProgramFromServerIfNeeded()
    }

    /// Carga la semana cacheada en el servidor si local está vacía o es otra semana.
    func loadPRVNProgramFromServerIfNeeded() async {
        await ensureOpen()
        guard let serverSync else { return }
        let monday = PRVNProgramStore.monday(containing: Date())
        let todayMondayKey = PRVNProgramStore.dayKey(for: monday)
        let needsLoad = PRVNProgramStore.shared.week == nil
            || PRVNProgramStore.shared.week?.weekStart != todayMondayKey
        guard needsLoad else { return }
        if let payload = await serverSync.fetchPRVNProgram(), payload.weekStart >= todayMondayKey {
            PRVNProgramStore.shared.importFromServer(pasteText: payload.pasteText, weekStartISO: payload.weekStart)
            return
        }
        _ = await syncPRVNProgram(weekStart: monday)
    }

    private func maybeAutoSyncPRVNProgram() async {
        guard isServerConfigured else { return }
        let monday = PRVNAutoSync.weekMondayToSync()
        let currentKey = PRVNProgramStore.dayKey(for: monday)
        let sundayAuto = PRVNAutoSync.shouldRunAutoSync()
        let localStale = PRVNProgramStore.shared.week?.weekStart != currentKey
        let serverStale = await isPRVNWeekStaleOnServer(currentMondayKey: currentKey)
        guard sundayAuto || localStale || serverStale else { return }
        guard await syncPRVNProgram(weekStart: monday) else { return }
        PRVNAutoSync.markSynced(weekMonday: monday)
    }

    /// True when the server cache is missing or older than the current calendar week.
    private func isPRVNWeekStaleOnServer(currentMondayKey: String) async -> Bool {
        guard let serverSync else { return true }
        guard let payload = await serverSync.fetchPRVNProgram() else { return true }
        return payload.weekStart < currentMondayKey
    }

    // MARK: - Sleep tab reads (M2)

    /// Unified session + daily for one local wake-day (Hoy / Sueño day picker).
    func nightContext(for date: Date) async -> (session: CachedSleepSession?, daily: DailyMetric?) {
        await ensureOpen()
        let dayKey = Self.localDayString(for: date)
        var session = await sleepSession(endingOnDay: dayKey)
        var daily = await dailyMetricForWakeDay(localDay: dayKey, session: session)
        if session == nil, let matchedDaily = daily {
            session = await sleepSession(matchingServerWakeDay: matchedDaily.day, nearLocalDay: dayKey)
            if session != nil {
                daily = await dailyMetricForWakeDay(localDay: dayKey, session: session) ?? matchedDaily
            }
        }
        if daily == nil, let session {
            daily = await dailyMetricForWakeDay(localDay: dayKey, session: session)
        }
        return (session, daily)
    }

    /// Night detail for a calendar day (local wake-day). Returns nil only when both are absent.
    func sleepDetail(for date: Date) async -> (session: CachedSleepSession?, daily: DailyMetric?)? {
        let ctx = await nightContext(for: date)
        if ctx.session == nil && ctx.daily == nil { return nil }
        return ctx
    }

    /// Returns sleep session + daily row for today (local wake-day), when either exists.
    func sleepDetail() async -> (session: CachedSleepSession?, daily: DailyMetric?)? {
        await sleepDetail(for: Date())
    }

    /// Returns up to `nights` most-recent sleep sessions, ordered oldest→newest, for the
    /// fall-asleep(startTs)/wake(endTs) trend chart on the Sleep tab.
    ///
    /// Fetches a slightly wider window (`nights + 2` days) so a session that started just before
    /// the window boundary is still included, then trims to the last `nights` entries.
    func sevenNightSleepWake(nights: Int = 7) async -> [CachedSleepSession] {
        await ensureOpen()
        guard let store else { return [] }

        let now = Int(Date().timeIntervalSince1970)
        let windowStart = now - (nights + 2) * 86_400
        let windowEnd   = now + 86_400
        let sessions = (try? await store.sleepSessions(deviceId: deviceId,
                                                       from: windowStart,
                                                       to: windowEnd,
                                                       limit: 40)) ?? []
        let primary = Self.primarySessionsPerWakeDay(sessions)
        return Array(primary.suffix(nights))
    }

    // MARK: - Raw HR series (downsampled stream, for Trends card + HeartRateDetailView)

    /// Fetch a downsampled raw HR series from the server for a given epoch-second window.
    /// Maps each (ts, bpm) pair to a TrendPoint so it can be fed directly to MetricChart.
    /// Uses a single server-side max_points-capped request — NOT the incremental pager.
    /// Returns [] on any network error or when unconfigured.
    func hrSeries(fromEpoch: Int, toEpoch: Int, maxPoints: Int) async -> [TrendPoint] {
        await ensureOpen()
        if isDemoPreviewActive {
            return DemoDataLoader.demoHrSeries(fromEpoch: fromEpoch, toEpoch: toEpoch, maxPoints: maxPoints)
        }
        guard let serverSync else { return [] }
        let raw = await serverSync.getHRSeries(fromEpoch: fromEpoch, toEpoch: toEpoch, maxPoints: maxPoints)
        return raw.map { pair in
            TrendPoint(
                id: "\(pair.ts)",
                date: Date(timeIntervalSince1970: TimeInterval(pair.ts)),
                value: Double(pair.bpm)
            )
        }
    }

    /// Fetch the RSA-derived respiratory-rate trend (breaths/min over time) for an
    /// epoch-second window, mapped to TrendPoints for the chart. Returns [] on error
    /// or when there aren't enough beats. The series is a signal-processing estimate.
    func respSeries(fromEpoch: Int, toEpoch: Int) async -> [TrendPoint] {
        await ensureOpen()
        guard let serverSync else { return [] }
        let raw = await serverSync.getRespSeries(fromEpoch: fromEpoch, toEpoch: toEpoch)
        return raw.map { pair in
            TrendPoint(
                id: "\(pair.ts)",
                date: Date(timeIntervalSince1970: TimeInterval(pair.ts)),
                value: pair.bpm
            )
        }
    }

    /// Fetch the nightly skin-temperature deviation trend (Δ°C from within-night median)
    /// for an epoch-second window, mapped to TrendPoints for the chart.
    /// Returns [] on error or when there is no data. Values are relative (not absolute °C).
    func tempSeries(fromEpoch: Int, toEpoch: Int) async -> [TrendPoint] {
        await ensureOpen()
        guard let serverSync else { return [] }
        let raw = await serverSync.getTempSeries(fromEpoch: fromEpoch, toEpoch: toEpoch)
        return raw.map { pair in
            TrendPoint(
                id: "\(pair.ts)",
                date: Date(timeIntervalSince1970: TimeInterval(pair.ts)),
                value: pair.delta
            )
        }
    }

    /// Fetch the windowed SpO₂ TREND (%) for an epoch-second window, mapped to TrendPoints
    /// for the chart. Quality-gated server-side: motion/low-perfusion samples are already
    /// excluded. Returns [] on error, unconfigured, or when all windows are rejected.
    /// Values are APPROXIMATE (ratio-of-ratios, uncalibrated) — useful as relative trend only.
    func spo2Series(fromEpoch: Int, toEpoch: Int) async -> [TrendPoint] {
        await ensureOpen()
        guard let serverSync else { return [] }
        let raw = await serverSync.getSpo2Series(fromEpoch: fromEpoch, toEpoch: toEpoch)
        return raw.map { pair in
            TrendPoint(
                id: "\(pair.ts)",
                date: Date(timeIntervalSince1970: TimeInterval(pair.ts)),
                value: pair.pct
            )
        }
    }

    // MARK: - Workouts (M5)

    /// Fetches auto-detected activities from the server for the given date range.
    /// Calls ensureOpen() to initialise the store/sync stack, then delegates to ServerSync.
    /// Returns [] when unconfigured (no API key), offline, or on parse error — never throws.
    func workouts(from: String, to: String) async -> [Workout] {
        await ensureOpen()
        if isDemoPreviewActive {
            return DemoDataLoader.demoWorkouts(deviceId: deviceId)
        }
        return await serverSync?.getWorkouts(from: from, to: to) ?? []
    }

    /// Workouts whose ``startTs`` falls in [fromEpoch, toEpoch) — local-day windows.
    func workouts(fromEpoch: Int, toEpoch: Int) async -> [Workout] {
        await ensureOpen()
        if isDemoPreviewActive {
            return DemoDataLoader.demoWorkouts(deviceId: deviceId)
        }
        return await serverSync?.getWorkouts(fromEpoch: fromEpoch, toEpoch: toEpoch) ?? []
    }

    /// Workouts in local calendar days [endingOn − daysBack, endingOn] (inclusive).
    /// Uses epoch bounds so midnight–02:00 local (Madrid) is not dropped vs UTC date queries.
    func workouts(lastDays daysBack: Int, endingOn date: Date = Date(), calendar: Calendar = .current) async -> [Workout] {
        let end = calendar.startOfDay(for: date)
        guard let from = calendar.date(byAdding: .day, value: -daysBack, to: end),
              let toExclusive = calendar.date(byAdding: .day, value: 1, to: end) else {
            return []
        }
        return await workouts(
            fromEpoch: Int(from.timeIntervalSince1970),
            toEpoch: Int(toExclusive.timeIntervalSince1970)
        )
    }

    /// Ventanas de estrés intradía (servidor) para un día calendario local.
    func stressPoints(for day: Date) async -> [StressPoint] {
        await ensureOpen()
        guard let serverSync, isServerConfigured, !isDemoPreviewActive else { return [] }
        let key = Self.localDayString(for: day)
        return await serverSync.fetchStress(fromDay: key, toDay: key)
    }

    /// Añade subidas de FC detectadas en el cliente para un día concreto.
    func supplementHRElevations(in workouts: [Workout], for day: Date, restingHr: Int?) async -> [Workout] {
        await ensureOpen()
        if isDemoPreviewActive { return workouts }

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: day)
        let startTs = Int(startOfDay.timeIntervalSince1970)
        let endTs: Int
        if cal.isDateInToday(day) {
            endTs = Int(Date().timeIntervalSince1970)
        } else if let next = cal.date(byAdding: .day, value: 1, to: startOfDay) {
            endTs = Int(next.timeIntervalSince1970)
        } else {
            return workouts
        }
        guard endTs > startTs else { return workouts }

        let hr = await hrSeries(fromEpoch: startTs, toEpoch: endTs, maxPoints: 14_400)
        let deduped = WorkoutDeduper.dedupe(workouts)
        let sustained = HRElevationDetector.detect(points: hr, restingHr: restingHr, deviceId: deviceId)
        let peaks = HRElevationDetector.detectPeaks(
            points: hr,
            restingHr: restingHr,
            deviceId: deviceId,
            existing: deduped + sustained
        )
        let morning = HRElevationDetector.detectMorningWake(
            points: hr,
            for: day,
            restingHr: restingHr,
            deviceId: deviceId,
            existing: deduped + sustained + peaks
        )
        return HRElevationDetector.merge(into: deduped, supplements: sustained + peaks + morning)
    }

    // MARK: - Workout calorie backfill (M7)

    /// Asks the server to recompute calorie estimates for workouts in [from, to] (YYYY-MM-DD UTC).
    /// Fire-and-forget: the caller should not await a meaningful result; returns false silently if
    /// unconfigured or the request fails. Never throws.
    @discardableResult
    func backfillWorkouts(from: String, to: String) async -> Bool {
        await ensureOpen()
        return await serverSync?.backfillWorkouts(from: from, to: to) ?? false
    }

    // MARK: - Baselines & calibration helpers

    /// Media de los últimos 30 días (excluye hoy UTC) para baselines estilo WHOOP.
    func thirtyDayBaselines() async -> BaselineCalculator.Averages {
        await ensureOpen()
        guard let store else { return BaselineCalculator.Averages() }
        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let todayDay = fmt.string(from: today)
        guard let fromDate = cal.date(byAdding: .day, value: -30, to: today) else {
            return BaselineCalculator.Averages()
        }
        let fromDay = fmt.string(from: fromDate)
        let rows = (try? await store.dailyMetrics(deviceId: deviceId, from: fromDay, to: todayDay)) ?? []
        return BaselineCalculator.thirtyDay(from: rows, excludingDay: todayDay)
    }

    /// Noches con sesión de sueño en los últimos `days` días.
    func sleepNightCount(days: Int = 30) async -> Int {
        await ensureOpen()
        guard let store else { return 0 }
        let now = Int(Date().timeIntervalSince1970)
        let from = now - days * 86_400
        let sessions = (try? await store.sleepSessions(deviceId: deviceId, from: from, to: now, limit: 200)) ?? []
        return sessions.count
    }

    // MARK: - Demo preview (métricas de referencia WHOOP oficial → caché local)

    /// Escribe métricas de vista previa en GRDB (no usa BLE ni servidor). Para comparar UI con WHOOP oficial.
    func loadDemoPreview() async {
        await ensureOpen()
        guard let store else {
            lastError = "No se pudo abrir la base de datos"
            return
        }
        let payload = DemoDataLoader.make(deviceId: deviceId)
        do {
            try await store.upsertDailyMetrics(payload.daily, deviceId: deviceId)
            try await store.upsertSleepSessions(payload.sessions, deviceId: deviceId)
            UserDefaults.standard.set(true, forKey: DemoDataLoader.activeKey)
            isDemoPreviewActive = true
            lastError = nil
            await load()
            lastRefreshedAt = Date()
        } catch {
            lastError = "Error al cargar vista previa"
        }
    }

    func clearDemoPreviewFlag() {
        UserDefaults.standard.set(false, forKey: DemoDataLoader.activeKey)
        isDemoPreviewActive = false
    }

    /// Quita la vista previa y borra métricas cacheadas localmente, luego intenta pull del servidor.
    func clearDemoPreview() async {
        await ensureOpen()
        clearDemoPreviewFlag()
        if let store {
            try? await store.clearCachedMetrics(deviceId: deviceId)
        }
        await refresh()
    }
}
