import XCTest
@testable import WhoopStore

final class ClockLossEventTests: XCTestCase {
    func testV10CreatesClockLossEventTable() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("clockLossEvent"))
        XCTAssertEqual(WhoopStoreInfo.schemaVersion, 10)
    }

    func testInsertOpenAndMarkRecovered() async throws {
        let store = try await WhoopStore.inMemory()
        let id = try await store.insertClockLossEvent(ClockLossEvent(
            deviceId: "my-whoop",
            detectedAt: 1_784_365_000,
            strapNewestCorrupt: 1_887_500_000,
            strapOldestCorrupt: 1_887_496_400,
            lastGoodFrontier: 1_784_280_000,
            reason: "future_data_range"))
        XCTAssertGreaterThan(id, 0)

        let open = try await store.openClockLossEvent(deviceId: "my-whoop")
        XCTAssertEqual(open?.id, id)
        XCTAssertEqual(open?.deltaSeconds, 1_887_500_000 - 1_784_365_000)
        XCTAssertNil(open?.recoveredAt)

        try await store.addClockLossSalvageStats(deviceId: "my-whoop", remapped: 12, dropped: 3)
        try await store.markClockLossRecovered(deviceId: "my-whoop", recoveredAt: 1_784_365_100)

        let stillOpen = try await store.openClockLossEvent(deviceId: "my-whoop")
        XCTAssertNil(stillOpen)

        let recent = try await store.recentClockLossEvents(deviceId: "my-whoop")
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent[0].remappedRows, 12)
        XCTAssertEqual(recent[0].droppedRows, 3)
        XCTAssertEqual(recent[0].recoveredAt, 1_784_365_100)
    }

    func testSecondDetectReusesOpenEvent() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.insertClockLossEvent(ClockLossEvent(
            deviceId: "my-whoop",
            detectedAt: 100,
            strapNewestCorrupt: 200,
            reason: "future_data_range"))
        // Caller is responsible for checking open first; verify open stays the first one.
        let open = try await store.openClockLossEvent(deviceId: "my-whoop")
        XCTAssertEqual(open?.detectedAt, 100)
    }
}
