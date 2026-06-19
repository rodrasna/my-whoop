import XCTest
@testable import OpenWhoop

final class MobilityTimingTests: XCTestCase {

    func testDailySessionTargetScalesWithRecovery() {
        let full = MobilityTiming.sessionTarget(kind: .daily, recoveryPercent: 80)
        XCTAssertEqual(full.minSec, 15 * 60)
        XCTAssertEqual(full.maxSec, 20 * 60)
        XCTAssertEqual(full.midpointMinutes, 17)

        let moderate = MobilityTiming.sessionTarget(kind: .daily, recoveryPercent: 50)
        XCTAssertEqual(moderate.minSec, 14 * 60)
        XCTAssertEqual(moderate.maxSec, 18 * 60)

        let low = MobilityTiming.sessionTarget(kind: .daily, recoveryPercent: 20)
        XCTAssertEqual(low.minSec, 12 * 60)
        XCTAssertEqual(low.maxSec, 15 * 60)
    }

    func testPostWorkoutAndPreSleepTargets() {
        let post = MobilityTiming.sessionTarget(kind: .postWorkout, recoveryPercent: 70)
        XCTAssertEqual(post.minSec, 8 * 60)
        XCTAssertEqual(post.maxSec, 12 * 60)

        let postLow = MobilityTiming.sessionTarget(kind: .postWorkout, recoveryPercent: 25)
        XCTAssertEqual(postLow.minSec, 6 * 60)

        let sleep = MobilityTiming.sessionTarget(kind: .preSleep)
        XCTAssertEqual(sleep.minSec, 12 * 60)
        XCTAssertEqual(sleep.maxSec, 15 * 60)
    }

    func testGuidedDurationByModeAndSession() {
        let staticEx = sampleExercise(mode: .staticHold)
        let dynamicEx = sampleExercise(mode: .dynamic)
        XCTAssertEqual(MobilityTiming.guidedDurationSec(for: staticEx, sessionKind: .daily), 90)
        XCTAssertEqual(MobilityTiming.guidedDurationSec(for: dynamicEx, sessionKind: .daily), 60)
        XCTAssertEqual(MobilityTiming.guidedDurationSec(for: staticEx, sessionKind: .postWorkout), 75)
        XCTAssertEqual(MobilityTiming.guidedDurationSec(for: staticEx, sessionKind: .preWorkout), 40)
    }

    func testDurationLabelFormatting() {
        XCTAssertEqual(MobilityTiming.durationLabel(seconds: 45), "45 s")
        XCTAssertEqual(MobilityTiming.durationLabel(seconds: 60), "1 min")
        XCTAssertEqual(MobilityTiming.durationLabel(seconds: 90), "1 min 30 s")
        XCTAssertEqual(MobilityTiming.durationLabel(seconds: 120), "2 min")
    }

    private func sampleExercise(mode: MobilityMode) -> MobilityExercise {
        MobilityExercise(
            id: "test-\(mode.rawValue)",
            name: "Test",
            description: "",
            focusAreas: [.hips],
            sessionKinds: [.daily],
            pose: .squat,
            youtubeURL: "https://example.com",
            durationSec: 60,
            intensity: .gentle,
            mobilityMode: mode
        )
    }
}
