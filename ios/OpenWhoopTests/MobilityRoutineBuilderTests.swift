import XCTest
@testable import OpenWhoop

final class MobilityRoutineBuilderTests: XCTestCase {

  private var catalog: [MobilityExercise] = []

  override func setUp() {
    super.setUp()
    catalog = MobilityCatalogLoader.loadExercises()
    XCTAssertFalse(catalog.isEmpty, "catalog must load from bundle")
  }

  func testDailyRespectsFocusAreas() {
    let ctx = MobilityRoutineBuilder.Context(
      dayKey: "2026-06-18",
      sessionKind: .daily,
      focusAreas: [.ankles],
      prvnDayType: nil
    )
    let routine = MobilityRoutineBuilder.build(catalog: catalog, context: ctx)
    XCTAssertEqual(routine.sessionKind, .daily)
    XCTAssertGreaterThanOrEqual(routine.exercises.count, 4)
    let hasAnkle = routine.exercises.contains { $0.focusAreas.contains(.ankles) }
    XCTAssertTrue(hasAnkle)
  }

  func testPreWorkoutHeavyPrioritizesHipsAnkles() {
    let ctx = MobilityRoutineBuilder.Context(
      dayKey: "2026-06-18",
      sessionKind: .preWorkout,
      focusAreas: [.wrists],
      prvnDayType: .heavy
    )
    let routine = MobilityRoutineBuilder.build(catalog: catalog, context: ctx)
    let priorityHits = routine.exercises.filter {
      $0.focusAreas.contains(.hips) || $0.focusAreas.contains(.ankles)
    }
    XCTAssertGreaterThanOrEqual(priorityHits.count, 2)
    XCTAssertTrue(routine.rationale.contains("Heavy"))
  }

  func testPreWorkoutWithSquatPatternPrioritizesAnkles() {
    let ctx = MobilityRoutineBuilder.Context(
      dayKey: "2026-06-19",
      sessionKind: .preWorkout,
      focusAreas: [.hips],
      prvnDayType: .mixed,
      movementPatterns: [.squat]
    )
    let routine = MobilityRoutineBuilder.build(catalog: catalog, context: ctx)
    XCTAssertTrue(routine.rationale.contains("sentadilla"))
    let ankleHits = routine.exercises.filter { $0.focusAreas.contains(.ankles) }
    XCTAssertGreaterThanOrEqual(ankleHits.count, 1)
  }

  func testLowRecoveryShortensRoutine() {
    let full = MobilityRoutineBuilder.Context(
      dayKey: "2026-06-20",
      sessionKind: .preWorkout,
      focusAreas: [.hips],
      prvnDayType: .engine,
      recoveryPercent: 80
    )
    let limited = MobilityRoutineBuilder.Context(
      dayKey: "2026-06-20",
      sessionKind: .preWorkout,
      focusAreas: [.hips],
      prvnDayType: .engine,
      recoveryPercent: 25
    )
    let a = MobilityRoutineBuilder.build(catalog: catalog, context: full)
    let b = MobilityRoutineBuilder.build(catalog: catalog, context: limited)
    XCTAssertGreaterThan(a.totalDurationSec, b.totalDurationSec)
  }

  func testDailyUsesAssessmentWeakAreas() {
    let ctx = MobilityRoutineBuilder.Context(
      dayKey: "2026-06-21",
      sessionKind: .daily,
      focusAreas: [.hips],
      assessmentWeakAreas: [.ankles]
    )
    let routine = MobilityRoutineBuilder.build(catalog: catalog, context: ctx)
    XCTAssertTrue(routine.rationale.contains("débiles"))
    XCTAssertTrue(routine.exercises.contains { $0.focusAreas.contains(.ankles) })
  }

  func testPreSleepOnlyGentle() {
    let ctx = MobilityRoutineBuilder.Context(
      dayKey: "2026-06-18",
      sessionKind: .preSleep,
      focusAreas: [.hips, .shoulders, .thoracic],
      prvnDayType: nil
    )
    let routine = MobilityRoutineBuilder.build(catalog: catalog, context: ctx)
    XCTAssertTrue(routine.exercises.allSatisfy { $0.intensity == .gentle })
  }

  func testDeterministicForSameDayKey() {
    let ctx = MobilityRoutineBuilder.Context(
      dayKey: "2026-06-20",
      sessionKind: .daily,
      focusAreas: [.hips, .shoulders],
      prvnDayType: nil
    )
    let a = MobilityRoutineBuilder.build(catalog: catalog, context: ctx)
    let b = MobilityRoutineBuilder.build(catalog: catalog, context: ctx)
    XCTAssertEqual(a.exercises.map(\.id), b.exercises.map(\.id))
  }

  func testCatalogDecodeWithMovementTags() throws {
    let loaded = try MobilityCatalogLoader.load()
    XCTAssertGreaterThanOrEqual(loaded.exercises.count, 25)
    let tagged = loaded.exercises.first { !$0.movementPatterns.isEmpty }
    XCTAssertNotNil(tagged)
    XCTAssertFalse(tagged?.name.isEmpty ?? true)
  }

  func testCatalogCoversAllMovementPatternsForPreWorkout() {
    let prePool = catalog.filter { $0.sessionKinds.contains(.preWorkout) }
    for pattern in MobilityMovementPattern.allCases {
      let matches = prePool.filter { $0.movementPatterns.contains(pattern) }
      XCTAssertGreaterThanOrEqual(
        matches.count,
        2,
        "Patrón \(pattern.rawValue) necesita al menos 2 ejercicios pre-entreno"
      )
    }
  }

  func testDailySessionTargetsFifteenToTwentyMinutes() {
    let ctx = MobilityRoutineBuilder.Context(
      dayKey: "2026-06-18",
      sessionKind: .daily,
      focusAreas: [.hips, .shoulders],
      prvnDayType: nil,
      recoveryPercent: 80
    )
    let routine = MobilityRoutineBuilder.build(catalog: catalog, context: ctx)
    let target = MobilityTiming.sessionTarget(kind: .daily, recoveryPercent: 80)
    XCTAssertGreaterThanOrEqual(routine.totalDurationSec, target.minSec)
    XCTAssertLessThanOrEqual(routine.totalDurationSec, target.maxSec + 90)
    XCTAssertGreaterThanOrEqual(routine.estimatedMinutes, 15)
    XCTAssertTrue(routine.steps.allSatisfy { $0.guidedDurationSec >= 45 })
    XCTAssertFalse(routine.focusSummary.isEmpty)
  }

  func testPreWorkoutIncludesPatternSpecificExercise() {
    let ctx = MobilityRoutineBuilder.Context(
      dayKey: "2026-06-20",
      sessionKind: .preWorkout,
      focusAreas: [.hips],
      prvnDayType: .mixed,
      movementPatterns: [.squat, .hinge],
      recoveryPercent: 75
    )
    let routine = MobilityRoutineBuilder.build(catalog: catalog, context: ctx)
    XCTAssertTrue(routine.exercises.contains { $0.movementPatterns.contains(.squat) })
    XCTAssertTrue(routine.exercises.contains { $0.movementPatterns.contains(.hinge) })
    let target = MobilityTiming.sessionTarget(kind: .preWorkout, recoveryPercent: 75)
    XCTAssertGreaterThanOrEqual(routine.totalDurationSec, target.minSec)
  }

  func testPostWorkoutTargetsEightToTwelveMinutes() {
    let ctx = MobilityRoutineBuilder.Context(
      dayKey: "2026-06-23",
      sessionKind: .postWorkout,
      focusAreas: [.hips],
      movementPatterns: [.squat, .hinge],
      recoveryPercent: 75
    )
    let routine = MobilityRoutineBuilder.build(catalog: catalog, context: ctx)
    XCTAssertEqual(routine.sessionKind, .postWorkout)
    let target = MobilityTiming.sessionTarget(kind: .postWorkout, recoveryPercent: 75)
    XCTAssertGreaterThanOrEqual(routine.totalDurationSec, target.minSec)
    XCTAssertLessThanOrEqual(routine.totalDurationSec, target.maxSec + 90)
    XCTAssertTrue(routine.exercises.allSatisfy { $0.intensity == .gentle || $0.mobilityMode == .staticHold })
  }
}
