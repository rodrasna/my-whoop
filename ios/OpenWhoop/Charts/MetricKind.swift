import SwiftUI
import Charts
import WhoopStore

enum MetricKind: String, Identifiable {
    case recovery
    case hrv
    case rhr
    case strain
    case sleepDuration
    case rawHR
    case spo2
    case respRate
    case skinTempDev

    var id: String { rawValue }

    static let dailyCases: [MetricKind] = [.recovery, .hrv, .rhr, .strain, .sleepDuration]

    /// Nightly health signals shown on the Salud tab (7-day trend cards).
    static let healthSignalCases: [MetricKind] = [.hrv, .rhr, .spo2, .respRate, .skinTempDev]

    // MARK: Display

    var title: String {
        switch self {
        case .recovery:      return "Recovery"
        case .hrv:           return "HRV"
        case .rhr:           return "Resting HR"
        case .strain:        return "Day Strain"
        case .sleepDuration: return "Sleep"
        case .rawHR:         return "Heart Rate"
        case .spo2:          return "SpO₂"
        case .respRate:      return "Respiratory Rate"
        case .skinTempDev:   return "Skin Temperature"
        }
    }

    /// Spanish UI label (app copy is mostly es).
    var localizedTitle: String {
        switch self {
        case .recovery:      return "Recuperación"
        case .hrv:           return "VFC"
        case .rhr:           return "FC en reposo"
        case .strain:        return "Esfuerzo"
        case .sleepDuration: return "Sueño"
        case .rawHR:         return "Frecuencia cardíaca"
        case .spo2:          return "SpO₂"
        case .respRate:      return "Frecuencia respiratoria"
        case .skinTempDev:   return "Temperatura cutánea"
        }
    }

    var unit: String {
        switch self {
        case .recovery:      return "%"
        case .hrv:           return "ms"
        case .rhr:           return "bpm"
        case .strain:        return "/ 21"
        case .sleepDuration: return "hr"
        case .rawHR:         return "bpm"
        case .spo2:          return "%"
        case .respRate:      return "rpm"
        case .skinTempDev:   return "Δ°C"
        }
    }

    // MARK: Color

    var color: Color {
        switch self {
        case .recovery:      return WH.Color.recoveryGreen
        case .hrv:           return WH.Color.teal
        case .rhr:           return WH.Color.textPrimary
        case .strain:        return WH.Color.strainBlue
        case .sleepDuration: return WH.Color.sleepPurple
        case .rawHR:         return WH.Color.recoveryRed
        case .spo2:          return WH.Color.sleepBlue
        case .respRate:      return WH.Color.textPrimary
        case .skinTempDev:   return WH.Color.recoveryYellow
        }
    }

    // MARK: Mark type

    enum MarkType { case line, bar }

    var markType: MarkType {
        switch self {
        case .recovery, .hrv, .rhr, .rawHR, .spo2, .respRate, .skinTempDev: return .line
        case .strain, .sleepDuration: return .bar
        }
    }

    // MARK: Fixed y-domain (nil = auto)

    var fixedYDomain: ClosedRange<Double>? {
        switch self {
        case .recovery: return 0...100
        case .strain:   return 0...21
        case .sleepDuration: return 0...12
        case .spo2:     return 90...100
        case .rawHR:    return nil
        default:        return nil
        }
    }

    var hasRecoveryBands: Bool { self == .recovery }
    var isStreamBacked: Bool { self == .rawHR }

    var supportsDetailView: Bool {
        switch self {
        case .rawHR: return false
        default: return true
        }
    }

    // MARK: Value formatting

    func format(_ value: Double) -> String {
        switch self {
        case .recovery:      return String(format: "%.0f%%", value)
        case .hrv:           return String(format: "%.0f ms", value)
        case .rhr:           return String(format: "%.0f bpm", value)
        case .strain:        return String(format: "%.1f", value)
        case .sleepDuration: return String(format: "%.1f hr", value)
        case .rawHR:         return String(format: "%.0f bpm", value)
        case .spo2:          return String(format: "%.1f%%", value)
        case .respRate:      return String(format: "%.1f rpm", value)
        case .skinTempDev:   return String(format: "%+.2f Δ°C", value)
        }
    }

    func formatShort(_ value: Double) -> String {
        switch self {
        case .recovery:      return String(format: "%.0f", value)
        case .hrv:           return String(format: "%.0f", value)
        case .rhr:           return String(format: "%.0f", value)
        case .strain:        return String(format: "%.1f", value)
        case .sleepDuration: return String(format: "%.1f", value)
        case .rawHR:         return String(format: "%.0f", value)
        case .spo2:          return String(format: "%.1f", value)
        case .respRate:      return String(format: "%.1f", value)
        case .skinTempDev:   return String(format: "%+.2f", value)
        }
    }

    // MARK: Data extraction from DailyMetric

    func value(from metric: DailyMetric) -> Double? {
        guard !isStreamBacked else { return nil }
        switch self {
        case .recovery:
            guard let r = metric.recovery else { return nil }
            return r * 100
        case .hrv:
            return metric.avgHrv
        case .rhr:
            return metric.restingHr.map { Double($0) }
        case .strain:
            return metric.strain
        case .sleepDuration:
            guard let m = metric.totalSleepMin, m > 0 else { return nil }
            return m / 60.0
        case .spo2:
            return metric.spo2Pct
        case .respRate:
            return metric.respRateBpm
        case .skinTempDev:
            return metric.skinTempDevC
        case .rawHR:
            return nil
        }
    }
}
