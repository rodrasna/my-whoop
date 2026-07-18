import XCTest
@testable import OpenWhoop

final class ClockPolicyTests: XCTestCase {
    func testInSyncDoesNotSet() {
        XCTAssertFalse(ClockPolicy.shouldSetClock(deviceClock: 1_000_000, wallNow: 1_000_001,
                                                  driftThreshold: 2))
    }
    func testDriftedSets() {
        XCTAssertTrue(ClockPolicy.shouldSetClock(deviceClock: 1_000_000, wallNow: 1_000_010,
                                                 driftThreshold: 2))
    }
    func testFrozenRtcSets() {
        XCTAssertTrue(ClockPolicy.shouldSetClock(deviceClock: 1_736_000_000, wallNow: 1_779_000_000,
                                                 driftThreshold: 2))
    }
    func testDeviceAheadSets() {
        XCTAssertTrue(ClockPolicy.shouldSetClock(deviceClock: 1_000_010, wallNow: 1_000_000,
                                                 driftThreshold: 2))
    }

    func testSaneRecentNewest() {
        let wall = 1_784_160_000 // ~2026-07-16
        XCTAssertTrue(ClockPolicy.isSaneWallRelative(wall - 3600, wallNow: wall))
        XCTAssertFalse(ClockPolicy.isClockLost(strapNewest: wall - 3600, wallNow: wall))
        XCTAssertFalse(ClockPolicy.isFutureCorrupt(strapNewest: wall - 3600, wallNow: wall))
    }

    func testMay2026NewestStillSaneInJuly() {
        let wall = 1_784_160_000 // ~2026-07-16
        let may10 = 1_778_371_200 // ~2026-05-10
        XCTAssertTrue(ClockPolicy.isSaneWallRelative(may10, wallNow: wall))
        XCTAssertFalse(ClockPolicy.isFutureCorrupt(strapNewest: may10, wallNow: wall))
    }

    func testFuture2029IsClockLost() {
        let wall = 1_784_160_000
        let oct2029 = 1_886_000_000
        XCTAssertFalse(ClockPolicy.isSaneWallRelative(oct2029, wallNow: wall))
        XCTAssertTrue(ClockPolicy.isClockLost(strapNewest: oct2029, wallNow: wall))
        XCTAssertTrue(ClockPolicy.isFutureCorrupt(strapNewest: oct2029, wallNow: wall))
    }

    func testNilNewestIsClockLostButNotFutureCorrupt() {
        XCTAssertTrue(ClockPolicy.isClockLost(strapNewest: nil, wallNow: 1_784_160_000))
        XCTAssertFalse(ClockPolicy.isFutureCorrupt(strapNewest: nil, wallNow: 1_784_160_000))
    }
}
