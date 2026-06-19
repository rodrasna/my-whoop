import XCTest
@testable import OpenWhoop

final class TrainingCoachCopyTests: XCTestCase {

    func testStrainAboveBaselinePhrase() {
        let report = TrainingDayCoachReport(
            day: "2026-06-16",
            style: "qualifier",
            activityType: "crossfit",
            primaryWorkoutId: "dev|1",
            summary: TrainingCoachSummary(
                strainVsBaselinePct: 18.5,
                avgHrVsBaselinePct: nil,
                z4plusVsBaselinePct: nil,
                verdict: "harder_than_usual",
                recoveryPct: 62,
                baselineSessionCount: 5
            ),
            blocks: [],
            insights: ["strain_above_baseline"],
            dataQuality: "good",
            inferredPlan: false,
            trainingContext: nil
        )
        let lines = TrainingCoachCopy.lines(for: report)
        XCTAssertTrue(lines.contains { $0.contains("Strain") && $0.contains("encima") })
        XCTAssertEqual(TrainingCoachCopy.headline(for: report), "Más duro de lo habitual")
    }

    func testRestDayHeadlineAndPhrase() {
        let report = TrainingDayCoachReport(
            day: "2026-06-16",
            style: nil,
            activityType: nil,
            primaryWorkoutId: nil,
            summary: TrainingCoachSummary(
                strainVsBaselinePct: nil,
                avgHrVsBaselinePct: nil,
                z4plusVsBaselinePct: nil,
                verdict: "rest_day",
                recoveryPct: 72,
                baselineSessionCount: nil
            ),
            blocks: [],
            insights: ["rest_day_planned"],
            dataQuality: "rest_day",
            inferredPlan: false,
            trainingContext: TrainingCoachTrainingContext(
                isRestDay: true,
                prvnReferenceDayKey: nil,
                userNote: "Descanso activo",
                source: "rest"
            )
        )
        XCTAssertEqual(TrainingCoachCopy.headline(for: report), "Descanso planificado")
        XCTAssertTrue(TrainingCoachCopy.lines(for: report).contains { $0.contains("Descanso planificado") })
        XCTAssertTrue(TrainingCoachCopy.lines(for: report).contains { $0.contains("Nota: Descanso activo") })
    }
}
