import Foundation
import WhoopStore

// MARK: - BaselineCalculator
// Medias simples de los últimos 30 días para baselines estilo WHOOP ("vs 30 días").

enum BaselineCalculator {

    struct Averages: Equatable {
        var recoveryPct: Double?
        var strain: Double?
        var hrv: Double?
        var rhr: Double?
        var sleepMin: Double?
    }

    /// Promedio de filas con valor no nulo. `excludingDay` omite hoy (YYYY-MM-DD UTC).
    static func thirtyDay(from rows: [DailyMetric], excludingDay: String? = nil) -> Averages {
        let filtered = rows.filter { excludingDay == nil || $0.day != excludingDay }
        return Averages(
            recoveryPct: average(filtered.compactMap { $0.recovery.map { $0 * 100 } }),
            strain: average(filtered.compactMap(\.strain)),
            hrv: average(filtered.compactMap(\.avgHrv)),
            rhr: average(filtered.compactMap { $0.restingHr.map(Double.init) }),
            sleepMin: average(filtered.compactMap(\.totalSleepMin))
        )
    }

    static func formatBaseline(_ value: Double?, decimals: Int = 0, unit: String? = nil) -> String? {
        guard let value else { return nil }
        let formatted: String
        if decimals == 0 {
            formatted = "\(Int(value.rounded()))"
        } else {
            formatted = String(format: "%.\(decimals)f", value)
        }
        if let unit { return "\(formatted) \(unit)" }
        return formatted
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
