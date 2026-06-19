import XCTest
@testable import OpenWhoop

final class PRVNMovementPatternParserTests: XCTestCase {

    func testDetectsOverheadAndSquatFromSnatchWOD() {
        let text = """
        FUERZA
        "Back Squat"
        5 x 5 @ 75%

        WOD
        AMRAP 12 min
        5 Power Snatch 60 kg
        10 Burpees
        """
        let patterns = PRVNMovementPatternParser.patterns(in: text)
        XCTAssertTrue(patterns.contains(.squat))
        XCTAssertTrue(patterns.contains(.overhead))
        XCTAssertTrue(patterns.contains(.locomotion))
    }

    func testFocusAreasFromOverheadPattern() {
        let areas = PRVNMovementPatternParser.focusAreas(for: [.overhead])
        XCTAssertTrue(areas.contains(.shoulders))
        XCTAssertTrue(areas.contains(.wrists))
    }

    func testPatternsFromProgramSkipsWarmup() {
        let program = PRVNDayProgram(
            id: "2026-06-18",
            weekday: 4,
            dayType: .skill,
            blocks: [
                ProgramBlock(kind: .warmup, body: "Row 500m easy"),
                ProgramBlock(kind: .strength, body: "\"Strict Press\"\n5 x 3"),
            ]
        )
        let patterns = PRVNMovementPatternParser.patterns(from: program)
        XCTAssertTrue(patterns.contains(.overhead))
        XCTAssertFalse(patterns.isEmpty)
    }

    func testBlocksDoneLimitsScanToSelectedBlocks() {
        let program = PRVNDayProgram(
            id: "2026-06-19",
            weekday: 5,
            dayType: .mixed,
            blocks: [
                ProgramBlock(kind: .strength, body: "\"Back Squat\"\n5 x 5"),
                ProgramBlock(kind: .metcon, body: "AMRAP 10 min\n10 Pull-ups\n10 Push-ups"),
            ]
        )
        let all = PRVNMovementPatternParser.patterns(from: program)
        XCTAssertTrue(all.contains(.squat))
        XCTAssertTrue(all.contains(.pull))

        let metconOnly = PRVNMovementPatternParser.patterns(
            from: program,
            blocksDone: [.metcon]
        )
        XCTAssertFalse(metconOnly.contains(.squat))
        XCTAssertTrue(metconOnly.contains(.pull))
        XCTAssertTrue(metconOnly.contains(.push))
    }

    func testAccessoryRowIgnoredWhenOnlyMetconSelected() {
        let program = PRVNDayProgram(
            id: "2026-06-20",
            weekday: 6,
            dayType: .engine,
            blocks: [
                ProgramBlock(kind: .metcon, body: "AMRAP 12\n15 Burpees"),
                ProgramBlock(kind: .accessory, body: "Row 500m"),
            ]
        )
        let metconOnly = PRVNMovementPatternParser.patterns(
            from: program,
            blocksDone: [.metcon]
        )
        XCTAssertTrue(metconOnly.contains(.locomotion))

        let full = PRVNMovementPatternParser.patterns(from: program)
        XCTAssertTrue(full.contains(.locomotion))
        let ranked = PRVNMovementPatternParser.rankedPatterns(from: program)
        XCTAssertEqual(ranked.first, .locomotion)
    }

    func testNoFalsePositiveFromPressSubstring() {
        let patterns = PRVNMovementPatternParser.patterns(in: "Express recovery and decompression breathing")
        XCTAssertFalse(patterns.contains(.push))
        XCTAssertFalse(patterns.contains(.overhead))
    }

    func testSpanishStrengthBlockDetectsSquat() {
        let program = PRVNDayProgram(
            id: "2026-06-21",
            weekday: 1,
            dayType: .heavy,
            blocks: [
                ProgramBlock(kind: .strength, body: "Sentadilla trasera\n5x5 @ 75%"),
            ]
        )
        let patterns = PRVNMovementPatternParser.patterns(from: program)
        XCTAssertTrue(patterns.contains(.squat))
    }

    func testRankedPatternsOrdersByBlockWeight() {
        let program = PRVNDayProgram(
            id: "2026-06-22",
            weekday: 2,
            dayType: .mixed,
            blocks: [
                ProgramBlock(kind: .accessory, body: "3x10 Push-ups"),
                ProgramBlock(kind: .metcon, body: "For time\n50 Wall balls"),
            ]
        )
        let ranked = PRVNMovementPatternParser.rankedPatterns(from: program)
        XCTAssertEqual(ranked.first, .squat, "WOD wall ball debería pesar más que accesorio push-up")
    }

    func testMinimumScoreFiltersWeakMatches() {
        let patterns = PRVNMovementPatternParser.patterns(in: "Easy recovery walk today")
        XCTAssertFalse(patterns.contains(.locomotion))
    }

    func testRankedPatternsRespectsMaxPatternsOption() {
        let program = PRVNDayProgram(
            id: "2026-06-23",
            weekday: 3,
            dayType: .mixed,
            blocks: [
                ProgramBlock(kind: .metcon, body: """
                AMRAP 20
                10 pull-ups
                10 push-ups
                10 air squats
                10 kettlebell swing
                farmer carry 100m
                """),
            ]
        )
        let ranked = PRVNMovementPatternParser.rankedPatterns(
            from: program,
            options: PRVNMovementPatternParser.ScanOptions(maxPatterns: 3)
        )
        XCTAssertLessThanOrEqual(ranked.count, 3)
        XCTAssertFalse(ranked.isEmpty)
    }
}
