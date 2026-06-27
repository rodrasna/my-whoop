import XCTest
@testable import OpenWhoop

final class DayActivitySectionsTests: XCTestCase {

    private func workout(kind: String? = nil, startTs: Int = 1_700_000_000) -> Workout {
        Workout(
            id: "d|w|\(startTs)",
            deviceId: "d",
            startTs: startTs,
            endTs: startTs + 600,
            avgHr: 120,
            peakHr: 140,
            strain: kind == "hr_elevation" ? nil : 9,
            kind: kind,
            durationS: 600,
            zoneTimePct: [:],
            avgHrrPct: nil,
            hrmax: nil,
            hrmaxSource: "",
            caloriesKcal: nil,
            caloriesKj: nil,
            motionVar: nil,
            hrPeaksPerMin: nil
        )
    }

    func testHrElevationMorningGoesToDailyRhythm() {
        var cal = Calendar.current
        cal.timeZone = .current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 7
        comps.minute = 0
        let morning = Int(cal.date(from: comps)!.timeIntervalSince1970)

        let w = workout(kind: "hr_elevation", startTs: morning)
        let assess = ActivityBoutClassifier.assess(w, among: [w], isConfirmed: false, isDismissed: false)

        let section = DayActivitySections.classify(
            w,
            assessment: assess,
            isConfirmed: false,
            isDismissed: false,
            hasActivityOnlyLabel: false
        )
        XCTAssertEqual(section, .dailyRhythm)
    }

    func testConfirmedHrElevationCountsAsWorkout() {
        let w = workout(kind: "hr_elevation")
        let assess = ActivityBoutClassifier.assess(w, among: [w], isConfirmed: true, isDismissed: false)
        let section = DayActivitySections.classify(
            w,
            assessment: assess,
            isConfirmed: true,
            isDismissed: false,
            hasActivityOnlyLabel: false
        )
        XCTAssertEqual(section, .workouts)
    }

    func testDismissedGoesToLife() {
        let w = workout()
        let assess = ActivityBoutClassifier.assess(w, among: [w], isConfirmed: false, isDismissed: true)
        let section = DayActivitySections.classify(
            w,
            assessment: assess,
            isConfirmed: false,
            isDismissed: true,
            hasActivityOnlyLabel: false
        )
        XCTAssertEqual(section, .life)
    }

    func testGroupPreservesSectionOrder() {
        var cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 8
        comps.minute = 0
        let morning = Int(cal.date(from: comps)!.timeIntervalSince1970)

        let motion = workout(kind: nil, startTs: morning + 7200)
        let hr = workout(kind: "hr_elevation", startTs: morning)
        let all = [hr, motion]
        let groups = DayActivitySections.group(
            workouts: all,
            assess: { w in
                ActivityBoutClassifier.assess(w, among: all, isConfirmed: false, isDismissed: false)
            },
            isConfirmed: { _ in false },
            isDismissed: { _ in false },
            hasActivityOnlyLabel: { _ in false }
        )
        XCTAssertEqual(groups.map(\.section), [.workouts, .dailyRhythm])
    }
}
