import XCTest
import WhoopProtocol
@testable import OpenWhoop

/// Unit tests for the type-47 high-freq-sync handshake pieces that are testable WITHOUT a live
/// CoreBluetooth peripheral. The full ordered command-emission path runs through `send()`, which
/// requires a real `peripheral` + `cmdCharacteristic` and early-returns when not connected — there
/// is no seam to capture sent frames headlessly, so the on-device emission order is verified
/// manually (see report). These tests pin the *pure* inputs to that path: the SET_CLOCK payload
/// builder and the frame encodings of the three new handshake commands.
@MainActor
final class BLEHandshakeTests: XCTestCase {

    // SET_CLOCK payload = <unix u32 LE> + <5 zero pad> = 9 bytes. Verified live 2026-07-13
    // (`-bleDebug` RX capture): this form gets a cmd=10 ACK from the strap and latches a lost RTC
    // (with a reboot); the 8-byte `<II` form the shipping builder previously used is silently
    // ignored — no ack — matching the 2026-05-24 recovery that also used the 9-byte form.
    func testSetClockPayloadIsUnixLE32Plus5ZeroPad() {
        let now: UInt32 = 0x6650_1234   // arbitrary fixed epoch
        let payload = BLEManager.setClockPayload(now: now)
        XCTAssertEqual(payload, [0x34, 0x12, 0x50, 0x66, 0, 0, 0, 0, 0])
        XCTAssertEqual(payload.count, 9)
    }

    func testSetClockPayloadUsesLittleEndianByteOrder() {
        let payload = BLEManager.setClockPayload(now: 1)
        XCTAssertEqual(payload, [0x01, 0x00, 0x00, 0x00, 0, 0, 0, 0, 0])
    }

    // The SET_CLOCK frame the handshake writes must pass crc8 + crc32 verification.
    func testSetClockFrameVerifies() {
        let frame = WhoopCommand.setClock.frame(seq: 1, payload: BLEManager.setClockPayload(now: 1_716_500_000))
        XCTAssertTrue(verifyFrame(frame).ok)
        XCTAssertEqual(frame[6], 10)  // cmd = SET_CLOCK
    }

    // ENTER_HIGH_FREQ_SYNC is the empty-payload step that unlocks type-47; verify the empty
    // payload framing matches the reference (inner = [type,seq,cmd] only).
    func testEnterHighFreqSyncEmptyPayloadFrame() {
        let frame = WhoopCommand.enterHighFreqSync.frame(seq: 1, payload: [])
        XCTAssertTrue(verifyFrame(frame).ok)
        XCTAssertEqual(frame[6], 96)
        let length = Int(frame[1]) | (Int(frame[2]) << 8)
        XCTAssertEqual(length, 3 + 4)   // no payload bytes
    }

    // The ack form the high-freq-sync path requires: HISTORICAL_DATA_RESULT payload = [0x01] + end_data.
    func testHistoricalDataResultAckFrameVerifies() {
        let endData: [UInt8] = [0x94, 0x26, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04]
        let frame = WhoopCommand.historicalDataResult.frame(seq: 1, payload: [0x01] + endData)
        XCTAssertTrue(verifyFrame(frame).ok)
        XCTAssertEqual(frame[6], 23)                    // cmd = HISTORICAL_DATA_RESULT
        XCTAssertEqual(frame[7], 0x01)                  // status byte
        XCTAssertEqual(Array(frame[8..<16]), endData)   // verbatim 8-byte end_data
    }

    // The backfill idle-watchdog must be re-armed ONLY by offload frames (47/48/49/50), never by
    // the live type-43/40 flood — otherwise the unstoppable ~2/s raw stream keeps the watchdog
    // alive forever and the session never completes/times-out, so upload never fires.
    func testOffloadFrameClassification() {
        func frame(type: UInt8) -> [UInt8] { [0xAA, 0x00, 0x00, 0x00, type, 0x00, 0x00] }
        XCTAssertTrue(BLEManager.isOffloadFrame(frame(type: 47)))   // HISTORICAL_DATA
        XCTAssertTrue(BLEManager.isOffloadFrame(frame(type: 48)))   // EVENT
        XCTAssertTrue(BLEManager.isOffloadFrame(frame(type: 49)))   // METADATA
        XCTAssertTrue(BLEManager.isOffloadFrame(frame(type: 50)))   // CONSOLE_LOGS
        XCTAssertFalse(BLEManager.isOffloadFrame(frame(type: 43)))  // REALTIME_RAW_DATA (flood)
        XCTAssertFalse(BLEManager.isOffloadFrame(frame(type: 40)))  // REALTIME_DATA
        XCTAssertFalse(BLEManager.isOffloadFrame([0xAA, 0x00]))     // too short
    }

    // The periodic backfill is the primary metric sync: re-run every 15 minutes (matching WHOOP).
    func testBackfillIntervalIsFifteenMinutes() {
        XCTAssertEqual(BLEManager.backfillIntervalSeconds, 900)
    }

    // The periodic re-trigger gate: only fire when connected + bonded and NOT already backfilling.
    // It must NOT consult `backfillStarted` (that guards the once-per-connect initial kick).
    func testShouldRunPeriodicBackfillGate() {
        // Happy path: connected, bonded, idle → run.
        XCTAssertTrue(BLEManager.shouldRunPeriodicBackfill(
            connected: true, bonded: true, backfilling: false))
        // Already backfilling → never interrupt an in-flight offload.
        XCTAssertFalse(BLEManager.shouldRunPeriodicBackfill(
            connected: true, bonded: true, backfilling: true))
        // Not bonded → custom channels can't flow, skip.
        XCTAssertFalse(BLEManager.shouldRunPeriodicBackfill(
            connected: true, bonded: false, backfilling: false))
        // Not connected → nothing to talk to.
        XCTAssertFalse(BLEManager.shouldRunPeriodicBackfill(
            connected: false, bonded: true, backfilling: false))
    }
}
