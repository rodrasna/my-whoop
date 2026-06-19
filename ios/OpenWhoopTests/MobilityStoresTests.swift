import XCTest
@testable import OpenWhoop

@MainActor
final class MobilityStoresTests: XCTestCase {

    private var assessmentDefaults: UserDefaults!
    private var completionDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        assessmentDefaults = UserDefaults(suiteName: "MobilityStoresTests.assessment")!
        assessmentDefaults.removePersistentDomain(forName: "MobilityStoresTests.assessment")
        completionDefaults = UserDefaults(suiteName: "MobilityStoresTests.completion")!
        completionDefaults.removePersistentDomain(forName: "MobilityStoresTests.completion")
        MobilityAssessmentStore.shared.resetForTesting()
        MobilityCompletionStore.shared.resetForTesting()
    }

    // MARK: - Assessment

    func testWeakAreasThreshold() {
        var scores = MobilityAssessmentScores(scores: [
            .hips: 2,
            .ankles: 5,
            .shoulders: 1,
        ])
        XCTAssertEqual(scores.weakAreas(), Set([.hips, .shoulders]))
        scores.scores[.hips] = 3
        XCTAssertEqual(scores.weakAreas(), Set([.shoulders]))
    }

    func testAssessmentOnboardingHiddenWhenComplete() {
        let store = MobilityAssessmentStore(defaults: assessmentDefaults)
        XCTAssertTrue(store.shouldShowOnboarding)
        for area in MobilityFocusArea.allCases {
            store.setScore(4, for: area)
        }
        XCTAssertFalse(store.shouldShowOnboarding)
        XCTAssertNotNil(store.scores.completedAt)
    }

    func testAssessmentSnoozeHidesBanner() {
        let store = MobilityAssessmentStore(defaults: assessmentDefaults)
        store.snoozeOnboarding(days: 7)
        XCTAssertFalse(store.shouldShowOnboarding)
        store.clearOnboardingSnooze()
        XCTAssertTrue(store.shouldShowOnboarding)
    }

    // MARK: - Completion analytics

    func testStreakCountsConsecutiveDays() {
        let today = Date()
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let entries = [
            MobilityCompletionEntry(
                dayKey: MetricsRepository.localDayString(for: today),
                sessionKind: .daily,
                exerciseCount: 8,
                completedAt: today
            ),
            MobilityCompletionEntry(
                dayKey: MetricsRepository.localDayString(for: yesterday),
                sessionKind: .preWorkout,
                exerciseCount: 6,
                completedAt: yesterday
            ),
        ]
        XCTAssertEqual(MobilityCompletionAnalytics.streak(entries: entries, through: today), 2)
    }

    func testWeekSummaryMarksSessions() {
        let store = MobilityCompletionStore(defaults: completionDefaults)
        let key = MetricsRepository.localDayString(for: Date())
        store.markCompleted(sessionKind: .daily, exerciseCount: 10, dayKey: key)
        let week = store.weekSummary()
        XCTAssertEqual(week.count, 7)
        let today = week.first { $0.isToday }
        XCTAssertEqual(today?.sessions, [.daily])
        XCTAssertEqual(store.currentStreak(), 1)
        XCTAssertEqual(store.totalSessions(lastDays: 7), 1)
    }

    func testMarkCompletedReplacesSameDaySession() {
        let store = MobilityCompletionStore(defaults: completionDefaults)
        let key = "2026-06-18"
        store.markCompleted(sessionKind: .daily, exerciseCount: 5, dayKey: key)
        store.markCompleted(sessionKind: .daily, exerciseCount: 12, dayKey: key)
        XCTAssertEqual(store.entries.filter { $0.dayKey == key && $0.sessionKind == .daily }.count, 1)
        XCTAssertEqual(store.entry(dayKey: key, sessionKind: .daily)?.exerciseCount, 12)
    }
}
