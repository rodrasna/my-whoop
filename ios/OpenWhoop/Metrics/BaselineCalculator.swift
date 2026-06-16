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

    /// Porcentajes medios de etapas de sueño (profundo/REM/ligero sobre TST; despierto sobre TIB).
    struct StagePercents: Equatable {
        var deep: Double?
        var rem: Double?
        var light: Double?
        var awake: Double?
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

    /// Media de % por etapa a partir de filas diarias con minutos de etapa (sobre TST).
    static func stagePercents(from rows: [DailyMetric]) -> StagePercents {
        var deepP: [Double] = [], remP: [Double] = [], lightP: [Double] = [], awakeP: [Double] = []
        for row in rows {
            guard let total = row.totalSleepMin, total > 0 else { continue }
            let asleep = (row.deepMin ?? 0) + (row.remMin ?? 0) + (row.lightMin ?? 0)
            let asleepDenom = max(asleep, 1)
            let tibDenom = max(total, 1)
            if let d = row.deepMin, d > 0 { deepP.append(d / asleepDenom * 100) }
            if let r = row.remMin, r > 0 { remP.append(r / asleepDenom * 100) }
            if let l = row.lightMin, l > 0 { lightP.append(l / asleepDenom * 100) }
            let awake = max(0, tibDenom - asleep)
            if awake > 0 { awakeP.append(awake / tibDenom * 100) }
        }
        return StagePercents(
            deep: average(deepP),
            rem: average(remP),
            light: average(lightP),
            awake: average(awakeP)
        )
    }
}
