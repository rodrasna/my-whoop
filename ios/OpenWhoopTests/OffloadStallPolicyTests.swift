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

    func testAwaitProbeOnlyWhileHoldActive() {
        XCTAssertTrue(OffloadStallPolicy.shouldAwaitDataRangeProbe(holdActive: true))
        XCTAssertFalse(OffloadStallPolicy.shouldAwaitDataRangeProbe(holdActive: false))
    }

    func testProbeTimeoutIsPositive() {
        XCTAssertGreaterThan(OffloadStallPolicy.rtcProbeTimeoutSeconds, 1.5)
    }

    func testExtendProbeOnEmptyDataRange() {
        XCTAssertTrue(OffloadStallPolicy.shouldExtendProbeOnEmptyDataRange(extensionsUsed: 0))
        XCTAssertTrue(OffloadStallPolicy.shouldExtendProbeOnEmptyDataRange(extensionsUsed: 1))
        XCTAssertFalse(OffloadStallPolicy.shouldExtendProbeOnEmptyDataRange(extensionsUsed: 2))
    }
}
