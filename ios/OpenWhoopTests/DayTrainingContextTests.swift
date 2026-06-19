import XCTest
@testable import OpenWhoop

@MainActor
final class DayTrainingContextTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "com.openwhoop.workoutDayPlans.v1")
    }

    func testRestDayClearsEffectivePrvn() {
        let store = WorkoutDayPlanStore()
        let prvnStore = PRVNProgramStore()
        let labels = ActivityLabelStore()

        store.set(WorkoutDayPlan(isRestDay: true), for: "2026-06-15")

        let ctx = store.trainingContext(
            dayKey: "2026-06-15",
            calendarDate: MetricsRepository.parseLocalDay("2026-06-15")!,
            workouts: [],
            labelStore: labels,
            prvnStore: prvnStore,
            isTrainingBout: { _ in false }
        )

        XCTAssertTrue(ctx.isRestDay)
        XCTAssertNil(ctx.effectivePrvnDay)
        XCTAssertEqual(ctx.sourceLabel, "Descanso")
    }

    func testReferenceDayUsesOtherPRVN() {
        let store = WorkoutDayPlanStore()
        let labels = ActivityLabelStore()
        let prvnStore = PRVNProgramStore()

        let monday = MetricsRepository.parseLocalDay("2026-06-08")!
        let text = """
        LUNES
        FUERZA
        Back squat 5x5

        SÁBADO
        METCON
        20 min AMRAP burpees
        """
        prvnStore.importText(text, weekStart: monday)
        guard let saturday = prvnStore.currentWeekDays.first(where: { $0.id != PRVNProgramStore.dayKey(for: monday) }) else {
            XCTFail("expected saturday in week")
            return
        }

        store.set(WorkoutDayPlan(
            blocksDone: [.metcon],
            prvnReferenceDayKey: saturday.id
        ), for: "2026-06-15")

        let ctx = store.trainingContext(
            dayKey: "2026-06-15",
            calendarDate: MetricsRepository.parseLocalDay("2026-06-15")!,
            workouts: [],
            labelStore: labels,
            prvnStore: prvnStore,
            isTrainingBout: { _ in false }
        )

        XCTAssertFalse(ctx.isRestDay)
        XCTAssertEqual(ctx.effectivePrvnDay?.id, saturday.id)
        XCTAssertEqual(ctx.blocksDone, [.metcon])
    }
}
