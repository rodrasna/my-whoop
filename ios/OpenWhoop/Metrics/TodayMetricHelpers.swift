import Foundation
import WhoopStore

// MARK: - TodayMetricHelpers
// Valores del día actual con prioridad sueño (VFC / FC reposo) y comparación con ayer.

enum TodayMetricHelpers {

    /// VFC de la última noche (sesión de sueño), no media diaria genérica.
    static func hrvMs(sleep: CachedSleepSession?, daily: DailyMetric?) -> Double? {
        sleep?.avgHrv ?? daily?.avgHrv
    }

    /// FC en reposo medida durante el sueño.
    static func restingHr(sleep: CachedSleepSession?, daily: DailyMetric?) -> Int? {
        sleep?.restingHr ?? daily?.restingHr
    }

    static func sleepWindowLabel(sleep: CachedSleepSession?) -> String? {
        guard let sleep else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let start = fmt.string(from: Date(timeIntervalSince1970: TimeInterval(sleep.startTs)))
        let end = fmt.string(from: Date(timeIntervalSince1970: TimeInterval(sleep.endTs)))
        return "de anoche \(start)–\(end)"
    }

    /// Fila diaria N días respecto a `anchor` (0 = hoy de anchor, -1 = ayer).
    static func dailyMetric(
        offset: Int,
        anchor: Date,
        today: DailyMetric?,
        selected: DailyMetric?,
        weekRows: [DailyMetric],
        isViewingToday: Bool
    ) -> DailyMetric? {
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .day, value: offset, to: anchor) else { return nil }
        let key = MetricsRepository.localDayString(for: day)
        if offset == 0 {
            if isViewingToday { return today }
            return selected
        }
        return weekRows.first { $0.day == key }
    }

    static func yesterdayComparison(
        current: Double?,
        yesterday: Double?,
        decimals: Int = 0,
        unit: String? = nil
    ) -> String? {
        guard let yesterday else { return nil }
        let formatted: String
        if decimals == 0 {
            formatted = "\(Int(yesterday.rounded()))"
        } else {
            formatted = String(format: "%.\(decimals)f", yesterday)
        }
        let suffix = unit.map { " \($0)" } ?? ""
        if current == nil { return "ayer \(formatted)\(suffix)" }
        return "ayer \(formatted)\(suffix)"
    }

    static func todayLabel(for anchor: Date, isViewingToday: Bool) -> String {
        isViewingToday ? "hoy" : shortDayLabel(anchor)
    }

    private static func shortDayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInYesterday(date) { return "ayer" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.setLocalizedDateFormatFromTemplate("EEE d/M")
        return fmt.string(from: date)
    }

    /// Recovery % for display: server value, or a local provisional estimate from last night.
    static func recoveryPercent(
        sleep: CachedSleepSession?,
        daily: DailyMetric?,
        sleepNights: Int
    ) -> (percent: Double, provisional: Bool)? {
        if let r = daily?.recovery {
            let pct = r * 100
            return (pct, sleepNights < 4)
        }
        guard sleepNights < 4,
              let estimate = estimatedProvisionalRecovery(sleep: sleep, daily: daily) else {
            return nil
        }
        return (estimate, true)
    }

    /// Mirrors server population-baseline path (approximate) for nights before recompute.
    private static func estimatedProvisionalRecovery(
        sleep: CachedSleepSession?,
        daily: DailyMetric?
    ) -> Double? {
        guard let hrv = hrvMs(sleep: sleep, daily: daily),
              let rhr = restingHr(sleep: sleep, daily: daily) else { return nil }

        let hrvZ = (hrv - 55.0) / 5.0
        let rhrZ = (58.0 - Double(rhr)) / 2.0
        let sleepEff = sleep?.efficiency ?? daily?.efficiency ?? 0.85
        let sleepZ = (sleepEff - 0.85) / 0.12
        let z = 0.60 * hrvZ + 0.20 * rhrZ + 0.15 * sleepZ
        let score = 100.0 / (1.0 + exp(-1.6 * (z - (-0.20))))
        return max(0, min(100, score))
    }

    /// Composite sleep score 0–100 for rings and hero (falls back to efficiency / duration).
    static func sleepScorePercent(daily: DailyMetric?, sleep: CachedSleepSession? = nil) -> Double? {
        if let s = daily?.sleepScore, s > 0 { return s }
        if let e = daily?.efficiency, e > 0 { return e * 100 }
        if let e = sleep?.efficiency, e > 0 { return e * 100 }
        if let m = daily?.totalSleepMin, m > 0 { return min(100, m / 480 * 100) }
        return nil
    }

    static func sleepScoreFraction(daily: DailyMetric?, sleep: CachedSleepSession? = nil) -> Double? {
        sleepScorePercent(daily: daily, sleep: sleep).map { $0 / 100.0 }
    }
}
