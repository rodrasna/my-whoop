import XCTest
@testable import OpenWhoop

final class ActivityRecommendationEngineTests: XCTestCase {

    private func ctx(
        recovery: Int? = 70,
        strain: Double? = 5,
        dayType: PRVNDayType = .heavy,
        feeling: MorningFeeling? = nil,
        hour: Int = 10,
        activities: Int = 0,
        trainingBouts: Int = 0
    ) -> ActivityRecommendationContext {
        let prvn = PRVNDayProgram(
            id: "2026-06-18",
            weekday: 4,
            dayType: dayType,
            blocks: dayType == .rest
                ? []
                : [ProgramBlock(kind: .strength, body: "\"Back Squat\"\n5 x 5")]
        )
        return ActivityRecommendationContext(
            dayKey: "2026-06-18",
            recoveryPercent: recovery,
            strainToday: strain,
            strainYesterday: 14,
            prvnDay: prvn,
            morningFeeling: feeling,
            activityCountToday: activities,
            trainingBoutCountToday: trainingBouts,
            hourOfDay: hour,
            isToday: true
        )
    }

    func testGreenRecoveryHeavySuggestsPushOrPreWOD() {
        let rec = ActivityRecommendationEngine.recommend(context: ctx(recovery: 75, strain: 13))
        XCTAssertTrue(rec?.kind == .push || rec?.kind == .mobilityPreWOD)
    }

    func testRedRecoveryHeavySuggestsModify() {
        let rec = ActivityRecommendationEngine.recommend(context: ctx(recovery: 28, strain: 2))
        XCTAssertEqual(rec?.kind, .modify)
    }

    func testRestDayLowRecoverySuggestsRest() {
        let rec = ActivityRecommendationEngine.recommend(
            context: ctx(recovery: 25, strain: 1, dayType: .rest)
        )
        XCTAssertNotNil(rec)
        XCTAssertTrue(rec?.kind == .rest || rec?.kind == .mobilityDaily)
    }

    func testBadMorningFeelingDowngradesRecommendation() {
        XCTAssertEqual(
            ActivityRecommendationEngine.effectiveRecoveryTier(recovery: 72, feeling: nil),
            .high
        )
        XCTAssertEqual(
            ActivityRecommendationEngine.effectiveRecoveryTier(recovery: 72, feeling: .veryBad),
            .medium
        )
    }

    func testSedentaryAfternoonWithNoActivity() {
        let rec = ActivityRecommendationEngine.recommend(
            context: ctx(recovery: 60, strain: 0, hour: 15, activities: 0)
        )
        XCTAssertEqual(rec?.kind, .sedentaryBreak)
    }

    func testStrainTargetForTiers() {
        let high = ActivityRecommendationEngine.strainTarget(for: .high)
        XCTAssertEqual(high.min, 12)
        XCTAssertEqual(high.max, 16)
        let low = ActivityRecommendationEngine.strainTarget(for: .low)
        XCTAssertEqual(low.max, 8)
    }

    func testPreWorkoutSkippedWhenMobilityAlreadyDone() {
        var c = ctx(recovery: 75, strain: 5)
        c.completedMobilitySessions = [.preWorkout]
        let rec = ActivityRecommendationEngine.recommend(context: c)
        XCTAssertNotEqual(rec?.kind, .mobilityPreWOD)
    }

    func testModifyLinksMobilityPreWorkout() {
        let rec = ActivityRecommendationEngine.recommend(context: ctx(recovery: 28, strain: 2))
        XCTAssertEqual(rec?.suggestedMobilitySession, .preWorkout)
    }

    func testWindDownLinksPreSleep() {
        let rec = ActivityRecommendationEngine.recommend(
            context: ctx(recovery: 60, strain: 12, hour: 21)
        )
        XCTAssertEqual(rec?.kind, .windDown)
        XCTAssertEqual(rec?.suggestedMobilitySession, .preSleep)
    }

    func testPostWorkoutAfterTrainingBout() {
        var c = ctx(recovery: 70, strain: 12, hour: 14, trainingBouts: 1)
        let rec = ActivityRecommendationEngine.recommend(context: c)
        XCTAssertEqual(rec?.kind, .mobilityPostWorkout)
        XCTAssertEqual(rec?.suggestedMobilitySession, .postWorkout)
    }

    func testPostWorkoutSkippedWhenAlreadyDone() {
        var c = ctx(recovery: 70, strain: 12, hour: 14, trainingBouts: 1)
        c.completedMobilitySessions = [.postWorkout]
        let rec = ActivityRecommendationEngine.recommend(context: c)
        XCTAssertNotEqual(rec?.kind, .mobilityPostWorkout)
    }

    func testNotTodayReturnsNil() {
        var c = ctx()
        c.isToday = false
        XCTAssertNil(ActivityRecommendationEngine.recommend(context: c))
    }

    func testPostStrainWindDownWhenWellAboveTarget() {
        let rec = ActivityRecommendationEngine.recommend(
            context: ctx(recovery: 75, strain: 18)
        )
        XCTAssertEqual(rec?.kind, .activeRecovery)
        XCTAssertEqual(rec?.primaryTitle, "Objetivo de strain cumplido")
    }

    func testFillStrainGapWhenHighRecoveryAndLowStrain() {
        let rec = ActivityRecommendationEngine.recommend(
            context: ctx(recovery: 80, strain: 5)
        )
        XCTAssertEqual(rec?.kind, .maintain)
        XCTAssertTrue(rec?.primaryTitle.contains("movimiento") == true
            || rec?.actions.contains(where: { $0.mobilitySession != nil }) == true)
    }

    func testSedentarySkippedWhenTrainingBoutExists() {
        let rec = ActivityRecommendationEngine.recommend(
            context: ctx(recovery: 60, strain: 8, hour: 15, activities: 0, trainingBouts: 1)
        )
        XCTAssertNotEqual(rec?.kind, .sedentaryBreak)
    }

    func testModifyMobilityDetailMentionsGuidedStretch() {
        let rec = ActivityRecommendationEngine.recommend(context: ctx(recovery: 28, strain: 2))
        let mobilityAction = rec?.actions.first { $0.mobilitySession == .preWorkout }
        XCTAssertTrue(mobilityAction?.detail.contains("Estiramientos guiados") == true)
        XCTAssertTrue(mobilityAction?.detail.contains("8–10 min") == true)
    }
}
