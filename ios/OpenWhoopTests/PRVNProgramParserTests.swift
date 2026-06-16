import XCTest
@testable import OpenWhoop

final class PRVNProgramParserTests: XCTestCase {

    func testParseSingleDayWithSpanishBlocks() {
        let text = """
        FUERZA
        Sentadilla trasera 5x5 @ 75%

        METCON
        AMRAP 12 min
        10 thrusters 43/30 kg
        10 pull-ups

        ACCESORIOS
        3x12 extensiones GHD
        """
        let monday = PRVNProgramStore.monday(containing: Date())
        let week = PRVNProgramParser.parse(text, weekStart: monday)
        XCTAssertEqual(week.days.count, 1)
        let day = week.days[0]
        XCTAssertEqual(day.blocks.count, 3)
        XCTAssertEqual(day.blocks[0].kind, .strength)
        XCTAssertEqual(day.blocks[1].kind, .metcon)
        XCTAssertEqual(day.blocks[2].kind, .accessory)
        XCTAssertEqual(day.dayType, .mixed)
    }

    func testParseWeekWithDayHeaders() {
        let text = """
        LUNES
        FUERZA
        Clean complex

        METCON
        EMOM 15 min

        MARTES
        METCON
        For time 5 rounds
        """
        let monday = date(from: "2026-06-08")
        let week = PRVNProgramParser.parse(text, weekStart: monday)
        XCTAssertEqual(week.days.count, 2)
        XCTAssertEqual(week.days[0].dayType, .mixed)
        XCTAssertEqual(week.days[1].dayType, .engine)
    }

    func testInferHeavyDay() {
        let blocks = PRVNProgramParser.parseBlocks("""
        FUERZA
        Back squat build to heavy single
        """)
        XCTAssertEqual(PRVNProgramParser.inferDayType(blocks: blocks), .heavy)
    }

    private func date(from yyyyMMdd: String) -> Date {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.date(from: yyyyMMdd)!
    }
}
