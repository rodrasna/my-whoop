import XCTest
@testable import OpenWhoop

final class WorkoutDeduperTests: XCTestCase {

    func testKeepsMotionWorkoutOverLongHRElevation() {
        let crossfit = Workout(
            id: "d|1",
            deviceId: "d",
            startTs: 1_000,
            endTs: 1_000 + 75 * 60,
            avgHr: 140,
            peakHr: 165,
            strain: 9.0,
            kind: nil,
            durationS: 75 * 60,
            zoneTimePct: [2: 40],
            avgHrrPct: 50,
            hrmax: 190,
            hrmaxSource: "",
            caloriesKcal: nil,
            caloriesKj: nil,
            motionVar: 1.2,
            hrPeaksPerMin: nil
        )
        let elevation = Workout(
            id: "d|2",
            deviceId: "d",
            startTs: 1_000 - 18 * 60,
            endTs: 1_000 + 216 * 60,
            avgHr: 115,
            peakHr: 125,
            strain: 1.0,
            kind: "hr_elevation",
            durationS: 216 * 60 + 18 * 60,
            zoneTimePct: [:],
            avgHrrPct: nil,
            hrmax: nil,
            hrmaxSource: "",
            caloriesKcal: nil,
            caloriesKj: nil,
            motionVar: nil,
            hrPeaksPerMin: nil
        )
        let kept = WorkoutDeduper.dedupe([elevation, crossfit])
        XCTAssertEqual(kept.count, 1)
        XCTAssertNil(kept[0].kind)
        XCTAssertEqual(kept[0].strain, 9.0)
    }
}
