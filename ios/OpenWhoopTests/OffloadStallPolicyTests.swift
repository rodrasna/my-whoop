import XCTest
@testable import OpenWhoop

final class OffloadStallPolicyTests: XCTestCase {
    func testHistoryCompleteClearsStallWhenRtcSane() {
        XCTAssertTrue(OffloadStallPolicy.shouldClearStallOnHistoryComplete(rtcKnownCorrupt: false))
    }

    func testHistoryCompleteKeepsStallWhenRtcCorrupt() {
        XCTAssertFalse(OffloadStallPolicy.shouldClearStallOnHistoryComplete(rtcKnownCorrupt: true))
    }

    func testVacuousCompleteOnlyWhenCorruptAndTiny() {
        XCTAssertTrue(OffloadStallPolicy.isVacuousHistoryComplete(frames: 20, rtcKnownCorrupt: true))
        XCTAssertTrue(OffloadStallPolicy.isVacuousHistoryComplete(frames: 100, rtcKnownCorrupt: true))
        XCTAssertFalse(OffloadStallPolicy.isVacuousHistoryComplete(frames: 101, rtcKnownCorrupt: true))
        XCTAssertFalse(OffloadStallPolicy.isVacuousHistoryComplete(frames: 20, rtcKnownCorrupt: false))
    }

    func testSalvageOncePerEpisode() {
        XCTAssertTrue(OffloadStallPolicy.shouldStartSalvage(alreadySalvagedThisEpisode: false))
        XCTAssertFalse(OffloadStallPolicy.shouldStartSalvage(alreadySalvagedThisEpisode: true))
    }
}
