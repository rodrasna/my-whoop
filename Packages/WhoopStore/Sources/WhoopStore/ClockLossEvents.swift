import Foundation
import GRDB

/// Persisted forensic record of a CLOCK-LOST episode on the strap RTC.
/// Used to (1) remap corrupt historical timestamps during salvage and
/// (2) keep a durable timeline of when the failure started / recovered.
public struct ClockLossEvent: Equatable, Codable, Sendable {
    public var id: Int64?
    public var deviceId: String
    /// Phone wall unix when the loss was first detected.
    public var detectedAt: Int
    /// Strap DATA_RANGE newest marker at detection (corrupt absolute RTC).
    public var strapNewestCorrupt: Int
    public var strapOldestCorrupt: Int?
    /// `hist_hr_frontier` at detection (last known-good historical HR ts), if any.
    public var lastGoodFrontier: Int?
    /// Why we opened the event: `future_data_range`, `offload_stall`, etc.
    public var reason: String
    /// Phone wall unix when a sane DATA_RANGE / successful repair closed the episode.
    public var recoveredAt: Int?
    /// Rows remapped during salvage offload (best-effort counter).
    public var remappedRows: Int
    /// Rows dropped because correction was still insane.
    public var droppedRows: Int

    public init(id: Int64? = nil,
                deviceId: String,
                detectedAt: Int,
                strapNewestCorrupt: Int,
                strapOldestCorrupt: Int? = nil,
                lastGoodFrontier: Int? = nil,
                reason: String,
                recoveredAt: Int? = nil,
                remappedRows: Int = 0,
                droppedRows: Int = 0) {
        self.id = id
        self.deviceId = deviceId
        self.detectedAt = detectedAt
        self.strapNewestCorrupt = strapNewestCorrupt
        self.strapOldestCorrupt = strapOldestCorrupt
        self.lastGoodFrontier = lastGoodFrontier
        self.reason = reason
        self.recoveredAt = recoveredAt
        self.remappedRows = remappedRows
        self.droppedRows = droppedRows
    }

    public var deltaSeconds: Int { strapNewestCorrupt - detectedAt }
}

extension WhoopStore {
    /// Insert a new open clock-loss event. Returns the row id.
    @discardableResult
    public func insertClockLossEvent(_ event: ClockLossEvent) async throws -> Int64 {
        try syncWrite { db in
            try db.execute(
                sql: """
                INSERT INTO clockLossEvent
                  (deviceId, detectedAt, strapNewestCorrupt, strapOldestCorrupt,
                   lastGoodFrontier, reason, recoveredAt, remappedRows, droppedRows)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    event.deviceId, event.detectedAt, event.strapNewestCorrupt,
                    event.strapOldestCorrupt, event.lastGoodFrontier, event.reason,
                    event.recoveredAt, event.remappedRows, event.droppedRows
                ])
            return db.lastInsertedRowID
        }
    }

    /// Close the most recent open event for `deviceId` (recoveredAt IS NULL).
    public func markClockLossRecovered(deviceId: String, recoveredAt: Int) async throws {
        try syncWrite { db in
            try db.execute(
                sql: """
                UPDATE clockLossEvent
                   SET recoveredAt = ?
                 WHERE id = (
                   SELECT id FROM clockLossEvent
                    WHERE deviceId = ? AND recoveredAt IS NULL
                    ORDER BY detectedAt DESC LIMIT 1
                 )
                """,
                arguments: [recoveredAt, deviceId])
        }
    }

    /// Add remapped/dropped counters to the open event (or latest if already closed).
    public func addClockLossSalvageStats(deviceId: String, remapped: Int, dropped: Int) async throws {
        guard remapped > 0 || dropped > 0 else { return }
        try syncWrite { db in
            try db.execute(
                sql: """
                UPDATE clockLossEvent
                   SET remappedRows = remappedRows + ?,
                       droppedRows  = droppedRows  + ?
                 WHERE id = (
                   SELECT id FROM clockLossEvent
                    WHERE deviceId = ?
                    ORDER BY detectedAt DESC LIMIT 1
                 )
                """,
                arguments: [remapped, dropped, deviceId])
        }
    }

    /// Most recent open (unrecovered) event for the device, if any.
    public func openClockLossEvent(deviceId: String) async throws -> ClockLossEvent? {
        try syncRead { db in
            try ClockLossEvent.fetchOne(
                db,
                sql: """
                SELECT * FROM clockLossEvent
                 WHERE deviceId = ? AND recoveredAt IS NULL
                 ORDER BY detectedAt DESC LIMIT 1
                """,
                arguments: [deviceId])
        }
    }

    /// Recent events newest-first (forensics / UI).
    public func recentClockLossEvents(deviceId: String, limit: Int = 20) async throws -> [ClockLossEvent] {
        try syncRead { db in
            try ClockLossEvent.fetchAll(
                db,
                sql: """
                SELECT * FROM clockLossEvent
                 WHERE deviceId = ?
                 ORDER BY detectedAt DESC
                 LIMIT ?
                """,
                arguments: [deviceId, limit])
        }
    }
}

extension ClockLossEvent: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "clockLossEvent"
}
