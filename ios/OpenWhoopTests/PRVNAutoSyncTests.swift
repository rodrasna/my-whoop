import XCTest
@testable import OpenWhoop

final class PRVNAutoSyncTests: XCTestCase {

    func testSundayTargetsNextMonday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 14
        comps.hour = 10
        let sunday = cal.date(from: comps)!
        let monday = PRVNAutoSync.weekMondayToSync(from: sunday, calendar: cal)
        XCTAssertEqual(cal.component(.weekday, from: monday), 2)
        XCTAssertEqual(cal.component(.day, from: monday), 15)
    }

    func testWednesdayUsesCurrentWeekMonday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 18
        let wednesday = cal.date(from: comps)!
        let monday = PRVNAutoSync.weekMondayToSync(from: wednesday, calendar: cal)
        XCTAssertEqual(cal.component(.day, from: monday), 15)
    }
}
