import SwiftUI
import WhoopStore

// MARK: - Ring detail hero screens (tap anillos en Hoy)

enum RingDestination: String, Identifiable, Hashable {
    case sleep, recovery, strain
    var id: String { rawValue }
}

// MARK: - SleepRingDetailView

struct SleepRingDetailView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @State private var detail: (session: CachedSleepSession, daily: DailyMetric?)?
    @State private var weekRows: [DailyMetric] = []

    private var scorePercent: Double? {
        if let e = detail?.session.efficiency, e > 0 { return e * 100 }
        if let e = detail?.daily?.efficiency, e > 0 { return e * 100 }
        return nil
    }

    var body: some View {
        ZStack {
            WH.Color.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: WH.Spacing.lg) {
                    if let score = scorePercent {
                        SleepPerformanceRing(scorePercent: score, size: WH.Ring.detailHeroDiameter)
                            .padding(.top, WH.Spacing.lg)
                    } else {
                        placeholderRing(label: "Sin datos de sueño")
                    }

                    if metrics.isDemoPreviewActive { previewChip }

                    if let detail {
                        sleepMetricsCard(session: detail.session, daily: detail.daily)
                    }

                    ringWeekChart(
                        title: "Sueño · últimos 7 días",
                        points: WeeklyChartBuilder.last7Days(from: weekRows) { m in
                            m.totalSleepMin.map { $0 / 60 }
                        },
                        maxValue: 10,
                        color: WH.Color.sleepPurple,
                        format: { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") }
                    )

                    NavigationLink(destination: MetricDetailView(kind: .sleepDuration)) {
                        detailLinkRow(title: "Historial completo", icon: "chart.bar")
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: WH.Spacing.xl)
                }
                .padding(WH.Spacing.md)
            }
        }
        .navigationTitle("Sueño")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private func load() async {
        detail = await metrics.sleepDetail()
        weekRows = await metrics.dailyLastDays(7)
    }

    private func sleepMetricsCard(session: CachedSleepSession, daily: DailyMetric?) -> some View {
        DashboardCard {
            metricRow(label: "Tiempo dormido",
                      value: formatMinutes(daily?.totalSleepMin ?? Double(session.endTs - session.startTs) / 60),
                      subtitle: TodayMetricHelpers.sleepWindowLabel(sleep: session))
            DashboardDivider()
            metricRow(label: "Eficiencia",
                      value: daily?.efficiency.map { "\(Int(($0 * 100).rounded()))%" }
                          ?? session.efficiency.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                      subtitle: "de esta noche")
            DashboardDivider()
            metricRow(label: "VFC",
                      value: session.avgHrv.map { String(format: "%.0f ms", $0) } ?? "—",
                      subtitle: "durante el sueño")
            DashboardDivider()
            metricRow(label: "FC en reposo",
                      value: session.restingHr.map { "\($0) lpm" } ?? "—",
                      subtitle: "durante el sueño")
        }
    }
}

// MARK: - RecoveryRingDetailView

struct RecoveryRingDetailView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @State private var weekRows: [DailyMetric] = []
    @State private var nightCount = 0

    private var recoveryPct: Double? {
        TodayMetricHelpers.recoveryPercent(
            sleep: metrics.lastNight,
            daily: metrics.today,
            sleepNights: nightCount
        )?.percent
    }

    private var recoveryProvisional: Bool {
        TodayMetricHelpers.recoveryPercent(
            sleep: metrics.lastNight,
            daily: metrics.today,
            sleepNights: nightCount
        )?.provisional ?? false
    }

    private var sleep: CachedSleepSession? { metrics.lastNight }

    var body: some View {
        ZStack {
            WH.Color.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: WH.Spacing.lg) {
                    if let pct = recoveryPct {
                        RecoveryRing(percent: pct, size: WH.Ring.detailHeroDiameter, provisional: recoveryProvisional)
                            .padding(.top, WH.Spacing.lg)
                    } else {
                        placeholderRing(label: "Sin recuperación aún")
                    }

                    if nightCount < 4 {
                        CalibrationBanner(
                            completedNights: nightCount,
                            title: "Calibrando tu recuperación",
                            footnote: recoveryPct != nil
                                ? "Este % es provisional — mejora cuando lleves 4 noches con el strap"
                                : "La recuperación necesita ~4 noches con el strap. Llevas \(nightCount)."
                        )
                    }

                    if metrics.isDemoPreviewActive { previewChip }

                    DashboardCard {
                        metricRow(label: "Recuperación hoy",
                                  value: recoveryPct.map { "\(Int($0.rounded()))%" } ?? "—",
                                  subtitle: recoveryProvisional ? "provisional · calibrando" : yesterdayRecoveryLabel)
                        DashboardDivider()
                        metricRow(label: "VFC",
                                  value: hrvValue,
                                  subtitle: TodayMetricHelpers.sleepWindowLabel(sleep: sleep) ?? "de anoche")
                        DashboardDivider()
                        metricRow(label: "FC en reposo",
                                  value: rhrValue,
                                  subtitle: "durante el sueño")
                        DashboardDivider()
                        metricRow(label: "SpO₂",
                                  value: metrics.today?.spo2Pct.map { String(format: "%.0f%%", $0) } ?? "—",
                                  subtitle: "hoy")
                        DashboardDivider()
                        metricRow(label: "Respiración",
                                  value: metrics.today?.respRateBpm.map { String(format: "%.1f rpm", $0) } ?? "—",
                                  subtitle: "hoy")
                    }

                    ringWeekChart(
                        title: "Recuperación · últimos 7 días",
                        points: WeeklyChartBuilder.last7Days(from: weekRows) { $0.recovery.map { $0 * 100 } },
                        maxValue: 100,
                        color: WH.Color.recoveryGreen,
                        format: { "\(Int($0.rounded()))" }
                    )

                    NavigationLink(destination: MetricDetailView(kind: .recovery)) {
                        detailLinkRow(title: "Historial completo", icon: "chart.line.uptrend.xyaxis")
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: WH.Spacing.xl)
                }
                .padding(WH.Spacing.md)
            }
        }
        .navigationTitle("Recuperación")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private var hrvValue: String {
        TodayMetricHelpers.hrvMs(sleep: sleep, daily: metrics.today)
            .map { String(format: "%.0f ms", $0) } ?? "—"
    }

    private var rhrValue: String {
        TodayMetricHelpers.restingHr(sleep: sleep, daily: metrics.today)
            .map { "\($0) lpm" } ?? "—"
    }

    private var yesterdayRecoveryLabel: String? {
        guard weekRows.count >= 2,
              let y = weekRows.dropLast().last?.recovery else { return nil }
        return "ayer \(Int((y * 100).rounded()))%"
    }

    private func load() async {
        weekRows = await metrics.dailyLastDays(7)
        nightCount = await metrics.sleepNightCount()
    }
}

// MARK: - StrainRingDetailView

struct StrainRingDetailView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @State private var weekRows: [DailyMetric] = []
    @State private var todayKcal: Double?

    private var strain: Double? { metrics.today?.strain }

    var body: some View {
        ZStack {
            WH.Color.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: WH.Spacing.lg) {
                    if let s = strain {
                        StrainRing(strain: s, size: WH.Ring.detailHeroDiameter)
                            .padding(.top, WH.Spacing.lg)
                    } else {
                        placeholderRing(label: "Sin esfuerzo registrado")
                    }

                    if metrics.isDemoPreviewActive { previewChip }

                    DashboardCard {
                        metricRow(label: "Esfuerzo hoy",
                                  value: strain.map {
                                      "\(WH.Ring.strainPercent($0))% · \(String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",")) / 21"
                                  } ?? "—",
                                  subtitle: yesterdayStrainLabel)
                        DashboardDivider()
                        metricRow(label: "Calorías hoy",
                                  value: todayKcal.map { "\(Int($0.rounded())) kcal" } ?? "—",
                                  subtitle: "de entrenos detectados")
                        DashboardDivider()
                        metricRow(label: "Entrenos hoy",
                                  value: metrics.today?.exerciseCount.map { "\($0)" } ?? "—",
                                  subtitle: "sesiones con esfuerzo")
                    }

                    ringWeekChart(
                        title: "Esfuerzo · últimos 7 días",
                        points: WeeklyChartBuilder.last7Days(from: weekRows) { $0.strain },
                        maxValue: 21,
                        color: WH.Color.strainBlue,
                        format: { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") }
                    )

                    NavigationLink(destination: MetricDetailView(kind: .strain)) {
                        detailLinkRow(title: "Historial completo", icon: "chart.bar.fill")
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: WH.Spacing.xl)
                }
                .padding(WH.Spacing.md)
            }
        }
        .navigationTitle("Esfuerzo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private var yesterdayStrainLabel: String? {
        guard weekRows.count >= 2,
              let y = weekRows.dropLast().last?.strain else { return nil }
        return String(format: "ayer %.1f", y).replacingOccurrences(of: ".", with: ",")
    }

    private func load() async {
        weekRows = await metrics.dailyLastDays(7)
        let today = MetricsRepository.utcDayString(for: Date())
        let workouts = await metrics.workouts(from: today, to: today)
        let kcal = workouts.compactMap(\.caloriesKcal).reduce(0, +)
        todayKcal = kcal > 0 ? kcal : nil
    }
}

// MARK: - Shared helpers

private func ringWeekChart(
    title: String,
    points: [WeeklyBarPoint],
    maxValue: Double,
    color: Color,
    format: @escaping (Double) -> String
) -> some View {
    Group {
        if points.contains(where: { $0.value > 0 }) {
            WeeklyBarChart(
                title: title,
                points: points,
                maxValue: maxValue,
                barColor: color,
                formatValue: format
            )
        }
    }
}

private func placeholderRing(label: String) -> some View {
    let d = WH.Ring.detailHeroDiameter
    return VStack(spacing: WH.Spacing.md) {
        ZStack {
            ProgressRing(progress: 0, color: WH.Color.textSecondary, diameter: d,
                         strokeWidth: WH.Ring.heroStroke(diameter: d), showGlow: false)
            Text(label)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: d * 0.62)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, WH.Spacing.lg)
    }
    .frame(maxWidth: .infinity)
}

private var previewChip: some View {
    HStack(spacing: WH.Spacing.xs) {
        Image(systemName: "sparkles")
            .foregroundStyle(WH.Color.sleepBlue)
        Text("Vista previa — datos de referencia")
            .font(WH.Font.caption)
            .foregroundStyle(WH.Color.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func metricRow(label: String, value: String, subtitle: String?) -> some View {
    HStack {
        Text(label.uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(WH.Color.textSecondary)
            .tracking(0.6)
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
                .monospacedDigit()
            if let subtitle {
                Text(subtitle)
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
    }
    .padding(.horizontal, WH.Spacing.md)
    .padding(.vertical, WH.Spacing.md)
}

private func detailLinkRow(title: String, icon: String) -> some View {
    HStack {
        Image(systemName: icon)
            .foregroundStyle(WH.Color.strainBlue)
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(WH.Color.textPrimary)
        Spacer()
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WH.Color.textSecondary)
    }
    .padding(WH.Spacing.md)
    .background(WH.Color.surface,
                in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
}

private func formatMinutes(_ minutes: Double) -> String {
    let total = Int(minutes.rounded())
    let h = total / 60
    let m = total % 60
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    if h > 0 { return "\(h)h" }
    return "\(m)m"
}
