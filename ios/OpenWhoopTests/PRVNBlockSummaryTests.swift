import XCTest
@testable import OpenWhoop

final class PRVNBlockSummaryTests: XCTestCase {

    func testStrengthListsMainLifts() {
        let block = ProgramBlock(kind: .strength, body: """
        Fuerza
        Back Squat
        For Load:
        5 Sets
        4 Back Squats @ 65%

        Weightlifting
        Parte A)
        Muscle Clean
        Por carga:
        4 Sets @ 50-55-60-65%

        Parte B)
        Power Clean
        Por carga:
        5 Sets @ 70-70-75-75-75%
        """)
        let summary = PRVNBlockSummary.oneLine(for: block)
        XCTAssertTrue(summary.contains("Back Squat"))
        XCTAssertTrue(summary.contains("Muscle Clean"))
        XCTAssertTrue(summary.contains("Power Clean"))
    }

    func testWODShowsNamedWorkout() {
        let block = ProgramBlock(kind: .metcon, body: """
        "Viper"
        Por tiempo:
        3 Rounds
        400m Run
        15 Burpee Pull-Ups
        """)
        let summary = PRVNBlockSummary.oneLine(for: block)
        XCTAssertTrue(summary.contains("Viper"))
    }

    func testWarmupSkipsNoise() {
        let block = ProgramBlock(kind: .warmup, body: """
        Warmup
        :45/:45 Pigeon Pose
        20 Banded Face Pulls
        """)
        let summary = PRVNBlockSummary.oneLine(for: block)
        XCTAssertFalse(summary.lowercased().contains("warmup"))
        XCTAssertTrue(summary.contains("Pigeon Pose") || summary.contains("Face Pulls"))
    }
}
