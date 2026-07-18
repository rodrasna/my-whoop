import XCTest
import WhoopProtocol
@testable import OpenWhoop

final class ClockLossPolicyTests: XCTestCase {
    // 2029-10-23 ~ like the live DATA_RANGE we saw.
    private let corruptNewest = 1_887_500_000
    private let wallAtDetect = 1_784_365_000   // ~2026-07-18

    func testDeltaAndCorrectMapsNewestToWall() {
        let anchor = ClockLossPolicy.anchor(
            strapNewest: corruptNewest,
            strapOldest: corruptNewest - 3_600,
            wallAtDetect: wallAtDetect,
            lastGoodFrontier: wallAtDetect - 86_400)
        XCTAssertEqual(anchor.deltaSeconds, corruptNewest - wallAtDetect)
        XCTAssertEqual(anchor.correct(corruptNewest), wallAtDetect)
        // One hour earlier on the corrupt axis → one hour before detect.
        XCTAssertEqual(anchor.correct(corruptNewest - 3_600), wallAtDetect - 3_600)
    }

    func testCorrectRejectsStillInsaneAfterRemap() {
        // Absurd delta that wouldn't come from a real DATA_RANGE, but guard the math.
        let anchor = ClockLossAnchor(
            wallAtDetect: wallAtDetect,
            strapNewestCorrupt: wallAtDetect + 10, // tiny delta
            strapOldestCorrupt: nil,
            lastGoodFrontier: nil)
        // Far-future ts with tiny Δ stays future → nil.
        XCTAssertNil(anchor.correct(corruptNewest))
    }

    func testRemapStreamsRewritesHRAndDropsUnfixable() {
        let anchor = ClockLossPolicy.anchor(
            strapNewest: corruptNewest,
            strapOldest: nil,
            wallAtDetect: wallAtDetect,
            lastGoodFrontier: wallAtDetect - 86_400)
        let streams = Streams(
            hr: [
                HRSample(ts: corruptNewest, bpm: 72),
                HRSample(ts: corruptNewest - 30, bpm: 74),
                HRSample(ts: wallAtDetect - 100, bpm: 60), // already sane — keep
            ],
            gravity: [
                GravitySample(ts: corruptNewest - 10, x: 0, y: 0, z: 1)
            ])
        let result = ClockLossPolicy.remapStreams(streams, anchor: anchor, wallNow: wallAtDetect)
        XCTAssertEqual(result.remapped, 3)
        XCTAssertEqual(result.dropped, 0)
        XCTAssertEqual(result.streams.hr.map(\.ts), [wallAtDetect, wallAtDetect - 30, wallAtDetect - 100])
        XCTAssertEqual(result.streams.gravity.first?.ts, wallAtDetect - 10)
    }

    func testDropInsaneTimestampsWithoutAnchor() {
        let streams = Streams(hr: [
            HRSample(ts: corruptNewest, bpm: 80),
            HRSample(ts: wallAtDetect, bpm: 70),
        ])
        let result = ClockLossPolicy.dropInsaneTimestamps(streams, wallNow: wallAtDetect)
        XCTAssertEqual(result.dropped, 1)
        XCTAssertEqual(result.streams.hr.map(\.ts), [wallAtDetect])
    }

    func testCorrectRejectsFarBeforeLastGoodFrontier() {
        let anchor = ClockLossPolicy.anchor(
            strapNewest: corruptNewest,
            strapOldest: nil,
            wallAtDetect: wallAtDetect,
            lastGoodFrontier: wallAtDetect - 3_600)
        // Would remap to ~2 days before last good → reject.
        let farCorrupt = corruptNewest - 200_000
        XCTAssertNil(anchor.correct(farCorrupt))
    }
}
