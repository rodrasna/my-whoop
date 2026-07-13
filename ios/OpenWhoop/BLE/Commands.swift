import Foundation
import WhoopProtocol

/// Curated, SAFE WHOOP command set for *sending* to the strap.
///
/// Raw values are the on-wire command codes (from whoomp/scripts/packet.py `CommandNumber`).
/// This is intentionally a *subset*: destructive / dangerous commands
/// (reboot, firmware load, force-trim, ship-mode, power-cycle, fuel-gauge reset, BLE DFU)
/// are deliberately EXCLUDED so the in-app command sender can never brick or wipe the device.
public enum WhoopCommand: UInt8, CaseIterable {
    case toggleRealtimeHR      = 3
    case reportVersionInfo     = 7
    case setClock              = 10
    case getClock              = 11
    case sendHistoricalData    = 22
    case historicalDataResult  = 23
    case getBatteryLevel       = 26
    case getDataRange          = 34
    case getHelloHarvard       = 35
    case getAdvertisingNameHarvard = 76
    case startRawData          = 81
    case stopRawData           = 82
    case enterHighFreqSync     = 96
    /// Leave high-frequency-sync mode. Sent defensively on connect to release a strap left parked in
    /// high-freq by an older app build (we no longer ENTER it — see the sync-hardening design). Payload
    /// [0x00]. Safe/reversible.
    case exitHighFreqSync      = 97
    case getExtendedBatteryInfo = 98
    case toggleIMUMode         = 106
    case enableOpticalData     = 107
    /// Fire a preset haptic pattern. Payload = `[patternId, numLoops, 0, 0, 0]` (5 bytes, from
    /// the device's preset table). patternId indexes the device's preset patterns (GET_ALL_HAPTICS_PATTERN
    /// reports 7 on harvard); the official app fires id=2. Safe/reversible — just buzzes the motor.
    case runHapticsPattern     = 79
    /// Stop an in-progress haptic pattern. Payload `[0x00]`. Safe/reversible.
    case stopHaptics           = 122
    /// The REAL control for the type-43 "R10/R11" realtime-raw stream (payload [0x01]=on / [0x00]=off).
    /// STOP_RAW_DATA(82) does NOT affect it; this one does. Sending [0x00] on connect stops the ~2/s
    /// raw flood that otherwise eats BLE airtime and dominates the strap's flash (blocking dense
    /// biometric retention + disconnected operation). Safe/reversible (just a data stream). Verified
    /// on-device: 2.1/s → 0/s, and it persists across reconnect.
    case sendR10R11Realtime    = 63

    // MARK: Alarm commands (confirmed for interoperability)
    /// Arm the strap's FIRMWARE alarm for a specific UTC time. The strap will buzz at that time
    /// even if the app is backgrounded or killed (event STRAP_DRIVEN_ALARM_EXECUTED=57).
    /// Payload: `setAlarmPayload(epochSec:)` → [0x01] + u32 LE + [0x00, 0x00] (7 bytes).
    /// IMPORTANT: always send SET_CLOCK (cmd 10) immediately before this to ensure the strap RTC
    /// is UTC-correct, otherwise the alarm fires at the wrong wall-clock time.
    case setAlarmTime          = 66
    /// Read the currently armed firmware alarm time. Payload [0x01].
    /// The strap replies with the armed epoch on the cmd-notify characteristic.
    case getAlarmTime          = 67
    /// Trigger an app-driven immediate alarm buzz now (event APP_DRIVEN_ALARM_EXECUTED=58).
    /// Payload [0x01]. Use `runHapticsPattern` with patternId=2 for a haptic-only alternative.
    case runAlarm              = 68
    /// Cancel / disarm the currently-armed firmware alarm. Payload [0x01].
    case disableAlarm          = 69

    /// Reboot the strap. Payload [0x00]; the link drops and the strap re-advertises in seconds.
    /// NOT exposed in the free-form command sender — reserved for the CLOCK-LOST recovery sequence
    /// (SET_CLOCK → REBOOT_STRAP to latch; see docs/specs/2026-05-24-whoop-protocol-complete.md §0-bis):
    /// a strap that loses its RTC (deep battery death) stops logging biometrics AND stops acking
    /// SET_CLOCK/GET_DATA_RANGE; only a reboot after SET_CLOCK restores historical logging.
    /// Verified on this strap 2026-05-24. Does not clear the data store.
    case rebootStrap           = 29

    /// Human-readable label for the command sender UI.
    public var label: String {
        switch self {
        case .toggleRealtimeHR:      return "Toggle Realtime HR"
        case .reportVersionInfo:     return "Report Version Info"
        case .setClock:              return "Set Clock"
        case .getClock:              return "Get Clock"
        case .sendHistoricalData:    return "Send Historical Data"
        case .historicalDataResult:  return "Historical Data Result"
        case .getBatteryLevel:       return "Get Battery Level"
        case .getDataRange:          return "Get Data Range"
        case .getHelloHarvard:       return "Get Hello (Harvard)"
        case .getAdvertisingNameHarvard: return "Get Advertising Name (Harvard)"
        case .startRawData:          return "Start Raw Data"
        case .stopRawData:           return "Stop Raw Data"
        case .enterHighFreqSync:     return "Enter High-Freq Sync"
        case .exitHighFreqSync:      return "Exit High-Freq Sync"
        case .getExtendedBatteryInfo:return "Get Extended Battery Info"
        case .toggleIMUMode:         return "Toggle IMU Mode"
        case .enableOpticalData:     return "Enable Optical Data"
        case .runHapticsPattern:     return "Run Haptics Pattern"
        case .stopHaptics:           return "Stop Haptics"
        case .sendR10R11Realtime:    return "R10/R11 Realtime (raw stream)"
        case .setAlarmTime:          return "Set Alarm Time"
        case .getAlarmTime:          return "Get Alarm Time"
        case .runAlarm:              return "Run Alarm"
        case .disableAlarm:          return "Disable Alarm"
        case .rebootStrap:           return "Reboot Strap"
        }
    }

    // MARK: Payload builders

    /// SET_ALARM_TIME (66) payload: Rev1 form (observed).
    /// Layout: `[0x01] + <epoch u32 LE> + [0x00, 0x00]` = 7 bytes total.
    /// The leading 0x01 is the sub-command / form byte; the 2-byte subseconds field is zero
    /// (the strap only uses the seconds portion). Always send SET_CLOCK (cmd 10) first so the
    /// strap RTC is UTC-correct, otherwise the alarm fires at the wrong wall-clock time.
    public static func setAlarmPayload(epochSec: UInt32) -> [UInt8] {
        [0x01,
         UInt8(epochSec & 0xFF),
         UInt8((epochSec >> 8) & 0xFF),
         UInt8((epochSec >> 16) & 0xFF),
         UInt8((epochSec >> 24) & 0xFF),
         0x00, 0x00]
    }
}

// MARK: - Alarm response parsing

enum AlarmResponseParser {
    /// Command-response payload as sliced by BLEManager (`frame[7..<len-4]`, i.e. AFTER the echoed
    /// cmd byte at frame[6]): `[rolling counter][status][...]`. Verified live 2026-07-13 via
    /// `-bleDebug` RX capture — SET_CLOCK ack `04 01 00 00 00`, DISABLE_ALARM ack `1e 01 01 …`.
    /// status 0x01 = OK. (The old check `payload[0] == 0x0a` assumed the payload began with the
    /// echoed cmd; it never matched a real frame — no ack was ever received until the 9-byte
    /// SET_CLOCK form landed, so it went unnoticed.)
    static func isOk(_ payload: [UInt8]) -> Bool {
        payload.count >= 2 && payload[1] == 0x01
    }

    static func epoch(from payload: [UInt8]) -> UInt32? {
        guard isOk(payload) else { return nil }
        if payload.count >= 9, payload[2] == 0x01 {
            let e = u32LE(payload, at: 3)
            return isPlausibleUnix(e) ? e : (e == 0 ? 0 : nil)
        }
        if payload.count >= 6 {
            let e = u32LE(payload, at: 2)
            if e == 0 || isPlausibleUnix(e) { return e }
        }
        return nil
    }

    private static func isPlausibleUnix(_ epoch: UInt32) -> Bool {
        epoch >= 1_700_000_000 && epoch <= 2_100_000_000
    }

    private static func u32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

extension WhoopCommand {
    static let commandType: UInt8 = 35

    /// Build a complete, framed COMMAND packet ready to write to char 61080002.
    ///
    /// Layout (verified against whoomp's WhoopPacket.framed_packet):
    /// `[0xAA][len u16 LE][crc8(len bytes)][type=35][seq][cmd][payload...][crc32 LE]`
    /// - `len` = (3 + payload.count) + 4  (inner type+seq+cmd+payload, plus the 4 envelope bytes)
    /// - `crc8` is over the 2 length bytes only
    /// - `crc32` (zlib) is over the inner `[type][seq][cmd][payload]`
    public func frame(seq: UInt8, payload: [UInt8] = [0x00]) -> [UInt8] {
        let inner: [UInt8] = [Self.commandType, seq, rawValue] + payload
        let length = UInt16(inner.count + 4)
        let lenBytes: [UInt8] = [UInt8(length & 0xFF), UInt8(length >> 8)]
        let headerCRC = crc8(lenBytes)
        let trailer = crc32(inner)
        let trailerBytes: [UInt8] = [
            UInt8(trailer & 0xFF),
            UInt8((trailer >> 8) & 0xFF),
            UInt8((trailer >> 16) & 0xFF),
            UInt8((trailer >> 24) & 0xFF),
        ]
        return [0xAA] + lenBytes + [headerCRC] + inner + trailerBytes
    }
}
