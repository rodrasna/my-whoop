import XCTest
@testable import OpenWhoop

@MainActor
final class SleepCheckInTests: XCTestCase {

    func testFactorPolarity() {
        XCTAssertTrue(SleepFactor.goodTemperature.isPositive)
        XCTAssertFalse(SleepFactor.alcohol.isPositive)
        XCTAssertEqual(SleepFactor.negativeFactors.count, 9)
        XCTAssertEqual(SleepFactor.positiveFactors.count, 4)
    }

    func testCheckInCodable() throws {
        let analysis = SleepCheckInAnalysis(
            sleepQualitySummary: "Bien pero con calor",
            perceivedCauses: ["Calor"],
            subjectiveRecoveryPct: 60,
            strapRecoveryPct: 82,
            alignment: "strap_higher",
            conclusion: "La pulsera dice más recovery que tu sensación."
        )
        let checkIn = SleepCheckIn(
            dayKey: "2026-06-18",
            morningFeeling: .good,
            onset: .hard,
            factors: [.heat, .feelRecovered],
            note: nil,
            savedAt: Date(timeIntervalSince1970: 1_000_000),
            recoveryPct: 0.42,
            sleepEfficiencyPct: 88,
            voiceTranscript: "dormí mal por el calor",
            analysis: analysis
        )
        let data = try JSONEncoder().encode(checkIn)
        let decoded = try JSONDecoder().decode(SleepCheckIn.self, from: data)
        XCTAssertEqual(decoded, checkIn)
    }

    func testFeelingScore() {
        let checkIn = SleepCheckIn(
            dayKey: "2026-06-18",
            morningFeeling: .great,
            onset: .easy,
            factors: [],
            note: nil,
            savedAt: Date(),
            recoveryPct: 0.8,
            sleepEfficiencyPct: 90
        )
        XCTAssertEqual(checkIn.feelingScore, 100)
        XCTAssertEqual(checkIn.recoveryPercent, 80)
    }

    func testMergeKeepsNewer() {
        let store = SleepCheckInStore.shared
        let day = "2099-01-01"
        defer { store.delete(dayKey: day) }

        let older = SleepCheckIn(
            dayKey: day,
            morningFeeling: .bad,
            onset: .hard,
            factors: [.noise],
            note: nil,
            savedAt: Date(timeIntervalSince1970: 1_000),
            recoveryPct: 0.3,
            sleepEfficiencyPct: 60
        )
        let newer = SleepCheckIn(
            dayKey: day,
            morningFeeling: .good,
            onset: .easy,
            factors: [.quiet],
            note: nil,
            savedAt: Date(timeIntervalSince1970: 2_000),
            recoveryPct: 0.7,
            sleepEfficiencyPct: 85
        )
        store.save(older)
        store.mergeFromServer([newer])
        XCTAssertEqual(store.entry(forDayKey: day)?.morningFeeling, .good)
    }
}
