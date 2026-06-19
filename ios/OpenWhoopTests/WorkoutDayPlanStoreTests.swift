import XCTest
@testable import OpenWhoop

@MainActor
final class WorkoutDayPlanStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "com.openwhoop.workoutDayPlans.v1")
    }

    func testResolveUsesSavedPlanOverInference() {
        let store = WorkoutDayPlanStore()
        let labels = ActivityLabelStore()
        let workout = Workout(
            id: "dev|1000",
            deviceId: "dev",
            startTs: 1000,
            endTs: 4600,
            avgHr: 140,
            peakHr: 175,
            strain: 12,
            kind: "crossfit",
            durationS: 3600,
            zoneTimePct: [:],
            avgHrrPct: 55,
            hrmax: 190,
            hrmaxSource: "",
            caloriesKcal: 400,
            caloriesKj: nil,
            motionVar: 1.0,
            hrPeaksPerMin: nil
        )
        store.set(WorkoutDayPlan(
            primaryWorkoutId: workout.id,
            activityType: .crossfit,
            crossfitStyle: .qualifier,
            blocksDone: [.metcon],
            note: "Open 26.2"
        ), for: "2026-06-15")

        let resolved = store.resolve(
            dayKey: "2026-06-15",
            workouts: [workout],
            labelStore: labels,
            prvnDay: nil,
            isTrainingBout: { _ in true }
        )

        XCTAssertEqual(resolved.activityType, ActivityType.crossfit)
        XCTAssertEqual(resolved.crossfitStyle, CrossFitSessionStyle.qualifier)
        XCTAssertEqual(resolved.blocksDone, [ProgramBlockKind.metcon])
        XCTAssertEqual(resolved.note, "Open 26.2")
        XCTAssertTrue(resolved.isUserDefined)
    }

    func testResolveFallsBackToPRVNBlocks() {
        let store = WorkoutDayPlanStore()
        let labels = ActivityLabelStore()
        let prvn = PRVNDayProgram(
            id: "2026-06-15",
            weekday: 1,
            dayType: .mixed,
            blocks: [
                ProgramBlock(kind: .warmup, body: "Row 500m"),
                ProgramBlock(kind: .metcon, body: "AMRAP 12"),
            ]
        )

        let resolved = store.resolve(
            dayKey: "2026-06-15",
            workouts: [],
            labelStore: labels,
            prvnDay: prvn,
            isTrainingBout: { _ in false }
        )

        XCTAssertEqual(resolved.blocksDone, [.warmup, .metcon])
        XCTAssertFalse(resolved.isUserDefined)
    }

    func testMergeFromServerKeepsNewerCopy() {
        let store = WorkoutDayPlanStore()
        store.mergeFromServer([
            (dayKey: "2026-06-15", plan: WorkoutDayPlan(note: "local", savedAt: 100)),
        ])
        store.mergeFromServer([
            (dayKey: "2026-06-15", plan: WorkoutDayPlan(note: "remote", savedAt: 200)),
            (dayKey: "2026-06-16", plan: WorkoutDayPlan(isRestDay: true, savedAt: 50)),
        ])
        XCTAssertEqual(store.plan(for: "2026-06-15")?.note, "remote")
        XCTAssertTrue(store.plan(for: "2026-06-16")?.isRestDay == true)
    }
}
