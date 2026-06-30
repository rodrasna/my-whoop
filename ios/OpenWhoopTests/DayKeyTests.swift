import XCTest
import WhoopStore
@testable import OpenWhoop

final class DayKeyTests: XCTestCase {

    func testLocalDayKeyUsesCalendarDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 16
        comps.hour = 13
        comps.minute = 30
        let afternoon = cal.date(from: comps)!
        let key = MetricsRepository.localDayString(for: afternoon, calendar: cal)
        XCTAssertEqual(key, "2026-06-16")
    }

    func testLocalDayKeyMatchesWeeklyChartBuilder() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let today = cal.startOfDay(for: Date())
        let key = MetricsRepository.localDayString(for: today, calendar: cal)
        let row = DailyMetric(
            day: key,
            totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
            disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil, strain: 12.0,
            exerciseCount: 2
        )
        let points = WeeklyChartBuilder.last7Days(
            from: [row],
            endingOn: today,
            highlightDayKey: key,
            value: { $0.strain },
            calendar: cal
        )
        XCTAssertEqual(points.last?.id, key)
        XCTAssertEqual(points.last?.value, 12.0)
        XCTAssertTrue(points.last?.isHighlighted == true)
    }

    func testUtcDayKeyStillUsesUtcMidnightEpoch() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 15
        comps.hour = 23
        comps.minute = 30
        let evening = cal.date(from: comps)!
        let key = MetricsRepository.utcDayString(for: evening, calendar: cal)
        XCTAssertEqual(key, "2026-06-14")
    }
}
