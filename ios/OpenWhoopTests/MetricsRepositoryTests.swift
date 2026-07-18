import XCTest
import WhoopStore
@testable import OpenWhoop

@MainActor
final class MetricsRepositoryTests: XCTestCase {

    // MARK: - Helpers

    private func makeRepo(store: WhoopStore) -> MetricsRepository {
        MetricsRepository(store: store, serverSync: nil, deviceId: "test-device")
    }

    private func dayString(offsetDays: Int, from now: Date = Date()) -> String {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.date(byAdding: .day, value: offsetDays, to: now) ?? now
        return MetricsRepository.localDayString(for: day)
    }

    private func seedDaily(_ store: WhoopStore) async throws -> [DailyMetric] {
        let days = [
            DailyMetric(day: dayString(offsetDays: -1), totalSleepMin: 400, efficiency: 0.85,
                        deepMin: 80, remMin: 100, lightMin: 220, disturbances: 2,
                        restingHr: 55, avgHrv: 58, recovery: 0.62, strain: 10, exerciseCount: 1),
            DailyMetric(day: dayString(offsetDays: 0), totalSleepMin: 430, efficiency: 0.90,
                        deepMin: 90, remMin: 110, lightMin: 230, disturbances: 1,
                        restingHr: 52, avgHrv: 65, recovery: 0.75, strain: 12, exerciseCount: 0),
        ]
        try await store.upsertDailyMetrics(days, deviceId: "test-device")
        return days
    }

    private func seedSleep(_ store: WhoopStore) async throws -> [CachedSleepSession] {
        // Timestamps in "now − a few days" range so load()'s 14-day window catches them.
        let now = Int(Date().timeIntervalSince1970)
        let sessions = [
            CachedSleepSession(startTs: now - 4 * 86_400, endTs: now - 4 * 86_400 + 28_800,
                               efficiency: 0.80, restingHr: 56, avgHrv: 55, stagesJSON: nil),
            CachedSleepSession(startTs: now - 1 * 86_400, endTs: now - 1 * 86_400 + 27_000,
                               efficiency: 0.88, restingHr: 53, avgHrv: 62, stagesJSON: nil),
        ]
        try await store.upsertSleepSessions(sessions, deviceId: "test-device")
        return sessions
    }

    // MARK: - load() pairs today / lastNight to this local wake-morning

    func testLoadSetsTodayToWakeDayDailyRow() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)

        let now = Date()
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let endTs = Int(todayStart.timeIntervalSince1970) + 7 * 3600
        let startTs = endTs - 7 * 3600
        let utcWake = MetricsRepository.utcDayString(fromEpoch: endTs)

        let session = CachedSleepSession(
            startTs: startTs, endTs: endTs,
            efficiency: 0.90, restingHr: 52, avgHrv: 65, stagesJSON: nil
        )
        let daily = DailyMetric(
            day: utcWake, totalSleepMin: 430, efficiency: 0.90,
            deepMin: 90, remMin: 110, lightMin: 230, disturbances: 1,
            restingHr: 52, avgHrv: 65, recovery: 0.75, strain: 12, exerciseCount: 0
        )
        try await store.upsertSleepSessions([session], deviceId: "test-device")
        try await store.upsertDailyMetrics([daily], deviceId: "test-device")

        await repo.load()

        XCTAssertEqual(repo.lastNight, session)
        XCTAssertEqual(repo.today?.day, utcWake)
        XCTAssertEqual(repo.today?.recovery, 0.75)
    }

    func testLoadIgnoresStaleSessionFromPreviousWakeDay() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)

        let now = Int(Date().timeIntervalSince1970)
        let stale = CachedSleepSession(
            startTs: now - 1 * 86_400, endTs: now - 1 * 86_400 + 27_000,
            efficiency: 0.99, restingHr: 50, avgHrv: 70, stagesJSON: nil
        )
        try await store.upsertSleepSessions([stale], deviceId: "test-device")

        await repo.load()

        XCTAssertNil(repo.lastNight, "must not surface yesterday's bout as today's lastNight")
        XCTAssertNil(repo.today)
    }

    func testLoadReturnsNilWhenCacheEmpty() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)

        await repo.load()

        XCTAssertNil(repo.today)
        XCTAssertNil(repo.lastNight)
    }

    // MARK: - daily(fromDay:toDay:) returns seeded range

    func testDailyRangeReturnsCorrectRows() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)
        let days = try await seedDaily(store)

        // Full window — should get both rows.
        let all = await repo.daily(fromDay: days[0].day, toDay: days[1].day)
        XCTAssertEqual(all, days)

        // Narrow window — should get only the later row.
        let narrow = await repo.daily(fromDay: days[1].day, toDay: days[1].day)
        XCTAssertEqual(narrow, [days[1]])
    }

    func testDailyRangeReturnsEmptyWhenNoMatch() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)
        _ = try await seedDaily(store)

        let result = await repo.daily(fromDay: "2026-01-01", toDay: "2026-01-31")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - sleepSessions(from:to:limit:) returns seeded range

    func testSleepSessionsRangeReturnsCorrectRows() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)
        let sessions = try await seedSleep(store)

        let now = Int(Date().timeIntervalSince1970)
        let all = await repo.sleepSessions(from: now - 10 * 86_400, to: now + 86_400, limit: 100)
        XCTAssertEqual(all, sessions)

        // Limit to 1 — should get only the earlier session (ASC order).
        let limited = await repo.sleepSessions(from: now - 10 * 86_400, to: now + 86_400, limit: 1)
        XCTAssertEqual(limited, [sessions[0]])
    }

    // MARK: - sleepDetail() pairs latest session with correct daily row

    func testSleepDetailReturnsLatestSessionWithMatchingDailyRow() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)

        // Seed two sessions; endTs of the latest falls on a deterministic UTC day.
        let now = Int(Date().timeIntervalSince1970)
        let s1 = CachedSleepSession(startTs: now - 4 * 86_400, endTs: now - 4 * 86_400 + 28_800,
                                    efficiency: 0.80, restingHr: 56, avgHrv: 55, stagesJSON: nil)
        // Latest session: ensure endTs lands on today's UTC date so the daily row matches.
        let s2 = CachedSleepSession(startTs: now - 1 * 86_400, endTs: now - 1 * 86_400 + 27_000,
                                    efficiency: 0.88, restingHr: 53, avgHrv: 62,
                                    stagesJSON: "[{\"start\":0,\"end\":1,\"stage\":\"deep\"}]")
        try await store.upsertSleepSessions([s1, s2], deviceId: "test-device")

        // Derive the UTC day of s2.endTs to build a matching daily row.
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        let s2Day = fmt.string(from: Date(timeIntervalSince1970: TimeInterval(s2.endTs)))

        let daily = DailyMetric(day: s2Day, totalSleepMin: 450, efficiency: 0.88,
                                deepMin: 95, remMin: 115, lightMin: 240, disturbances: 1,
                                restingHr: 53, avgHrv: 62, recovery: 0.78, strain: 9, exerciseCount: 0,
                                spo2Pct: 96.8, skinTempDevC: 0.2, respRateBpm: 14.5)
        // Seed a daily row for a different day too (should NOT be returned).
        let otherDaily = DailyMetric(day: "2026-01-01", totalSleepMin: 300, efficiency: 0.70,
                                     deepMin: 50, remMin: 60, lightMin: 190, disturbances: 5,
                                     restingHr: 60, avgHrv: 45, recovery: 0.50, strain: 15, exerciseCount: 2)
        try await store.upsertDailyMetrics([daily, otherDaily], deviceId: "test-device")

        let wakeDate = Date(timeIntervalSince1970: TimeInterval(s2.endTs))
        let result = await repo.sleepDetail(for: wakeDate)

        XCTAssertNotNil(result, "sleepDetail must return a result when sessions exist")
        XCTAssertEqual(result?.session, s2, "sleepDetail must return the latest session")
        XCTAssertNotNil(result?.daily, "sleepDetail must pair the daily row for the session's endTs day")
        XCTAssertEqual(result?.daily?.day, s2Day)
        let pairedDaily = try XCTUnwrap(result?.daily)
        XCTAssertEqual(try XCTUnwrap(pairedDaily.spo2Pct), 96.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(pairedDaily.skinTempDevC), 0.2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(pairedDaily.respRateBpm), 14.5, accuracy: 0.001)
    }

    func testSleepDetailReturnsNilWhenNoSessions() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)

        let result = await repo.sleepDetail()
        XCTAssertNil(result, "sleepDetail must return nil when the cache is empty")
    }

    func testSleepDetailDailyIsNilWhenNoDailyRowForThatDay() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)

        let now = Int(Date().timeIntervalSince1970)
        let session = CachedSleepSession(startTs: now - 86_400, endTs: now - 86_400 + 25_000,
                                         efficiency: 0.85, restingHr: 54, avgHrv: 60, stagesJSON: nil)
        try await store.upsertSleepSessions([session], deviceId: "test-device")
        // Intentionally do NOT seed any daily row.

        let wakeDate = Date(timeIntervalSince1970: TimeInterval(session.endTs))
        let result = await repo.sleepDetail(for: wakeDate)
        XCTAssertNotNil(result, "sleepDetail returns the session even without a daily row")
        XCTAssertEqual(result?.session, session)
        XCTAssertNil(result?.daily, "daily must be nil when no matching row exists")
    }

    func testSleepDetailPairsUtcDailyRowWhenLocalWakeDayDiffers() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 15
        comps.hour = 1
        comps.minute = 0
        let wakeLocal = try XCTUnwrap(cal.date(from: comps))
        let endTs = Int(wakeLocal.timeIntervalSince1970)
        let startTs = endTs - 7 * 3600

        let session = CachedSleepSession(
            startTs: startTs, endTs: endTs,
            efficiency: 0.88, restingHr: 53, avgHrv: 62,
            stagesJSON: "[{\"start\":\(startTs),\"end\":\(endTs),\"stage\":\"light\"}]"
        )
        try await store.upsertSleepSessions([session], deviceId: "test-device")

        let utcWakeDay = MetricsRepository.utcDayString(fromEpoch: endTs)
        XCTAssertEqual(utcWakeDay, "2026-07-14", "01:00 Madrid still counts as prior UTC wake-day")

        let daily = DailyMetric(
            day: utcWakeDay, totalSleepMin: 420, efficiency: 0.88,
            deepMin: 80, remMin: 95, lightMin: 245, disturbances: 1,
            restingHr: 53, avgHrv: 62, recovery: 0.78, strain: 9, exerciseCount: 0
        )
        try await store.upsertDailyMetrics([daily], deviceId: "test-device")

        let result = await repo.sleepDetail(for: wakeLocal)
        XCTAssertEqual(result?.session, session)
        XCTAssertEqual(result?.daily?.day, utcWakeDay)
        XCTAssertEqual(result?.daily?.totalSleepMin, 420)
    }

    func testSleepDetailReturnsDailyWhenSessionMissing() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)

        let daily = DailyMetric(
            day: "2026-07-15", totalSleepMin: 400, efficiency: 0.88,
            deepMin: 70, remMin: 90, lightMin: 240, disturbances: 2,
            restingHr: 54, avgHrv: 58, recovery: 0.72, strain: 8, exerciseCount: 0
        )
        try await store.upsertDailyMetrics([daily], deviceId: "test-device")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 15
        comps.hour = 12
        let noon = try XCTUnwrap(cal.date(from: comps))

        let result = await repo.sleepDetail(for: noon)
        XCTAssertNil(result?.session)
        XCTAssertEqual(result?.daily?.day, "2026-07-15")
    }

    func testWakeDaysDoNotShareSameDailyRow() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!

        func night(on day: Int, hour: Int) throws -> (CachedSleepSession, DailyMetric, Date) {
            var comps = DateComponents()
            comps.year = 2026; comps.month = 7; comps.day = day; comps.hour = hour
            let wake = try XCTUnwrap(cal.date(from: comps))
            let endTs = Int(wake.timeIntervalSince1970)
            let startTs = endTs - 7 * 3600
            let utcDay = MetricsRepository.utcDayString(fromEpoch: endTs)
            let session = CachedSleepSession(
                startTs: startTs, endTs: endTs,
                efficiency: day == 14 ? 0.88 : 0.62,
                restingHr: 54, avgHrv: 55, stagesJSON: nil
            )
            let daily = DailyMetric(
                day: utcDay,
                totalSleepMin: day == 14 ? 420 : 310,
                efficiency: day == 14 ? 0.88 : 0.62,
                deepMin: 70, remMin: 80, lightMin: 200, disturbances: day == 14 ? 1 : 4,
                restingHr: 54, avgHrv: 55, recovery: 0.7, strain: 8, exerciseCount: 0
            )
            return (session, daily, wake)
        }

        let (s14, d14, wake14) = try night(on: 14, hour: 7)
        let (s15, d15, wake15) = try night(on: 15, hour: 7)
        try await store.upsertSleepSessions([s14, s15], deviceId: "test-device")
        try await store.upsertDailyMetrics([d14, d15], deviceId: "test-device")

        let r14 = await repo.sleepDetail(for: wake14)
        let r15 = await repo.sleepDetail(for: wake15)
        XCTAssertEqual(r14?.daily?.efficiency, 0.88)
        XCTAssertEqual(r15?.daily?.efficiency, 0.62)
        XCTAssertNotEqual(r14?.daily?.day, r15?.daily?.day)
    }

    // MARK: - sevenNightSleepWake() count + ordering

    func testSevenNightSleepWakeReturnsCorrectCountOldestFirst() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)

        // Seed 10 sessions spread over the last 12 days, 1 per day.
        let now = Int(Date().timeIntervalSince1970)
        var sessions: [CachedSleepSession] = []
        for i in 0..<10 {
            let start = now - (10 - i) * 86_400
            sessions.append(CachedSleepSession(startTs: start, endTs: start + 25_200,
                                               efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil))
        }
        try await store.upsertSleepSessions(sessions, deviceId: "test-device")

        let result = await repo.sevenNightSleepWake(nights: 7)

        XCTAssertEqual(result.count, 7, "sevenNightSleepWake must return exactly 7 sessions")
        // Verify oldest→newest ordering (startTs monotonically increasing).
        for i in 1..<result.count {
            XCTAssertLessThan(result[i - 1].startTs, result[i].startTs,
                              "sessions must be ordered oldest→newest")
        }
        // The 7 returned must be the 7 most-recent of the 10 seeded.
        XCTAssertEqual(result.map { $0.startTs }, sessions.suffix(7).map { $0.startTs })
    }

    func testSevenNightSleepWakeReturnsEmptyWhenNoSessions() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)

        let result = await repo.sevenNightSleepWake(nights: 7)
        XCTAssertTrue(result.isEmpty, "sevenNightSleepWake must return [] when no sessions cached")
    }

    func testSevenNightSleepWakeReturnsAllWhenFewerThanNights() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)

        let now = Int(Date().timeIntervalSince1970)
        let session = CachedSleepSession(startTs: now - 2 * 86_400, endTs: now - 2 * 86_400 + 28_000,
                                         efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil)
        try await store.upsertSleepSessions([session], deviceId: "test-device")

        let result = await repo.sevenNightSleepWake(nights: 7)
        XCTAssertEqual(result.count, 1, "returns all available sessions when fewer than nights")
        XCTAssertEqual(result[0], session)
    }

    // MARK: - refresh() with nil serverSync does not crash; isRefreshing ends false

    func testRefreshWithNilServerSyncDoesNotCrashAndLoadsCache() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = makeRepo(store: store)
        _ = try await seedDaily(store)
        _ = try await seedSleep(store)

        await repo.refresh()

        XCTAssertFalse(repo.isRefreshing, "isRefreshing must be false after refresh completes")
        // seedSleep only has past nights — today/lastNight stay nil until a bout ends this morning.
        XCTAssertNil(repo.today)
        XCTAssertNil(repo.lastNight)
    }
}
