import SwiftUI
import WhoopStore

// MARK: - Ring detail hero screens (tap anillos en Hoy)

enum RingDestination: String, Identifiable, Hashable {
    case sleep, recovery, strain
    var id: String { rawValue }
}

// MARK: - SleepRingDetailView

struct SleepRingDetailView: View {
    let anchorDate: Date

    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var tabRouter: RootTabRouter
    @State private var detail: (session: CachedSleepSession, daily: DailyMetric?)?
    @State private var weekRows: [DailyMetric] = []
    @State private var weekNights: [CachedSleepSession] = []

    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(anchorDate)
    }

    private var dayLabel: String {
        TodayMetricHelpers.todayLabel(for: anchorDate, isViewingToday: isViewingToday)
    }

    private var scorePercent: Double? {
        TodayMetricHelpers.sleepScorePercent(daily: detail?.daily, sleep: detail?.session)
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

                    if let insight = sleepInsightText {
                        RingInsightCard(text: insight)
                    }

                    if let detail {
                        sleepMetricsCard(session: detail.session, daily: detail.daily)
                    }

                    ringWeekChart(
                        title: "Sueño · últimos 7 días",
                        points: WeeklyChartBuilder.last7Days(
                            from: weekRows,
                            endingOn: anchorDate,
                            highlightDayKey: MetricsRepository.localDayString(for: anchorDate)
                        ) { m in
                            m.totalSleepMin.map { $0 / 60 }
                        },
                        maxValue: 10,
                        color: WH.Color.sleepPurple,
                        format: { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") },
                        onSelectDay: selectChartDay
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
        .navigationTitle("Sueño · \(dayLabel)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task(id: anchorDate) { await load() }
    }

    private func load() async {
        let dayKey = MetricsRepository.localDayString(for: anchorDate)
        let sleep = await metrics.sleepSession(endingOnDay: dayKey)
        let daily = await metrics.dailyMetric(forDay: dayKey)
        if let sleep {
            detail = (session: sleep, daily: daily)
        } else {
            detail = nil
        }
        weekRows = await metrics.dailyLastDays(7, endingOn: anchorDate)
        weekNights = await metrics.sevenNightSleepWake(nights: 7)
    }

    private func selectChartDay(_ dayKey: String) {
        guard let date = MetricsRepository.parseLocalDay(dayKey) else { return }
        tabRouter.selectedDate = date
    }

    private var sleepInsightText: String? {
        let reg = SleepQualityBuilder.regularityScore(from: weekNights)
        guard let ctx = RingInsightCopy.sleepContext(
            session: detail?.session,
            daily: detail?.daily,
            regularityPct: reg
        ) else { return nil }
        return RingInsightCopy.sleep(ctx)
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
    let anchorDate: Date

    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var tabRouter: RootTabRouter
    @State private var weekRows: [DailyMetric] = []
    @State private var nightCount = 0
    @State private var dayMetric: DailyMetric?
    @State private var nightSleep: CachedSleepSession?

    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(anchorDate)
    }

    private var dayLabel: String {
        TodayMetricHelpers.todayLabel(for: anchorDate, isViewingToday: isViewingToday)
    }

    private var recoveryPct: Double? {
        TodayMetricHelpers.recoveryPercent(
            sleep: nightSleep,
            daily: dayMetric,
            sleepNights: nightCount
        )?.percent
    }

    private var recoveryProvisional: Bool {
        TodayMetricHelpers.recoveryPercent(
            sleep: nightSleep,
            daily: dayMetric,
            sleepNights: nightCount
        )?.provisional ?? false
    }

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

                    if let pct = recoveryPct {
                        RingInsightCard(text: RingInsightCopy.recovery(percent: pct, provisional: recoveryProvisional))
                    }

                    DashboardCard {
                        metricRow(label: "Recuperación · \(dayLabel)",
                                  value: recoveryPct.map { "\(Int($0.rounded()))%" } ?? "—",
                                  subtitle: recoveryProvisional ? "provisional · calibrando" : yesterdayRecoveryLabel)
                        DashboardDivider()
                        metricRow(label: "VFC",
                                  value: hrvValue,
                                  subtitle: TodayMetricHelpers.sleepWindowLabel(sleep: nightSleep) ?? "de anoche")
                        DashboardDivider()
                        metricRow(label: "FC en reposo",
                                  value: rhrValue,
                                  subtitle: "durante el sueño")
                        DashboardDivider()
                        metricRow(label: "SpO₂",
                                  value: dayMetric?.spo2Pct.map { String(format: "%.0f%%", $0) } ?? "—",
                                  subtitle: dayLabel)
                        DashboardDivider()
                        metricRow(label: "Respiración",
                                  value: dayMetric?.respRateBpm.map { String(format: "%.1f rpm", $0) } ?? "—",
                                  subtitle: dayLabel)
                    }

                    ringWeekChart(
                        title: "Recuperación · últimos 7 días",
                        points: WeeklyChartBuilder.last7Days(
                            from: weekRows,
                            endingOn: anchorDate,
                            highlightDayKey: MetricsRepository.localDayString(for: anchorDate)
                        ) { $0.recovery.map { $0 * 100 } },
                        maxValue: 100,
                        color: WH.Color.recoveryGreen,
                        format: { "\(Int($0.rounded()))" },
                        onSelectDay: selectChartDay
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
        .navigationTitle("Recuperación · \(dayLabel)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task(id: anchorDate) { await load() }
    }

    private var hrvValue: String {
        TodayMetricHelpers.hrvMs(sleep: nightSleep, daily: dayMetric)
            .map { String(format: "%.0f ms", $0) } ?? "—"
    }

    private var rhrValue: String {
        TodayMetricHelpers.restingHr(sleep: nightSleep, daily: dayMetric)
            .map { "\($0) lpm" } ?? "—"
    }

    private var yesterdayRecoveryLabel: String? {
        let key = MetricsRepository.localDayString(for: anchorDate)
        guard let idx = weekRows.firstIndex(where: { $0.day == key }), idx > 0,
              let y = weekRows[idx - 1].recovery else { return nil }
        return "día anterior \(Int((y * 100).rounded()))%"
    }

    private func load() async {
        let dayKey = MetricsRepository.localDayString(for: anchorDate)
        dayMetric = await metrics.dailyMetric(forDay: dayKey)
        nightSleep = await metrics.sleepSession(endingOnDay: dayKey)
        weekRows = await metrics.dailyLastDays(7, endingOn: anchorDate)
        nightCount = await metrics.sleepNightCount()
    }

    private func selectChartDay(_ dayKey: String) {
        guard let date = MetricsRepository.parseLocalDay(dayKey) else { return }
        tabRouter.selectedDate = date
    }
}

// MARK: - StrainRingDetailView

struct StrainRingDetailView: View {
    let anchorDate: Date

    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var tabRouter: RootTabRouter
    @State private var weekRows: [DailyMetric] = []
    @State private var dayMetric: DailyMetric?
    @State private var dayKcal: Double?

    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(anchorDate)
    }

    private var dayLabel: String {
        TodayMetricHelpers.todayLabel(for: anchorDate, isViewingToday: isViewingToday)
    }

    private var strain: Double? { dayMetric?.strain }

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

                    if let s = strain {
                        RingInsightCard(text: RingInsightCopy.strain(s))
                    }

                    DashboardCard {
                        metricRow(label: "Esfuerzo · \(dayLabel)",
                                  value: strain.map {
                                      "\(WH.Ring.strainPercent($0))% · \(String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",")) / 21"
                                  } ?? "—",
                                  subtitle: yesterdayStrainLabel)
                        DashboardDivider()
                        metricRow(label: "Calorías",
                                  value: dayKcal.map { "\(Int($0.rounded())) kcal" } ?? "—",
                                  subtitle: "de entrenos detectados")
                        DashboardDivider()
                        metricRow(label: "Entrenos",
                                  value: dayMetric?.exerciseCount.map { "\($0)" } ?? "—",
                                  subtitle: "sesiones con esfuerzo")
                    }

                    ringWeekChart(
                        title: "Esfuerzo · últimos 7 días",
                        points: WeeklyChartBuilder.last7Days(
                            from: weekRows,
                            endingOn: anchorDate,
                            highlightDayKey: MetricsRepository.localDayString(for: anchorDate)
                        ) { $0.strain },
                        maxValue: 21,
                        color: WH.Color.strainBlue,
                        format: { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") },
                        onSelectDay: selectChartDay
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
        .navigationTitle("Esfuerzo · \(dayLabel)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task(id: anchorDate) { await load() }
    }

    private var yesterdayStrainLabel: String? {
        let key = MetricsRepository.localDayString(for: anchorDate)
        guard let idx = weekRows.firstIndex(where: { $0.day == key }), idx > 0,
              let y = weekRows[idx - 1].strain else { return nil }
        return String(format: "día anterior %.1f", y).replacingOccurrences(of: ".", with: ",")
    }

    private func load() async {
        let dayKey = MetricsRepository.localDayString(for: anchorDate)
        dayMetric = await metrics.dailyMetric(forDay: dayKey)
        weekRows = await metrics.dailyLastDays(7, endingOn: anchorDate)
        let workouts = await metrics.workouts(from: dayKey, to: dayKey)
        let kcal = workouts.compactMap(\.caloriesKcal).reduce(0, +)
        dayKcal = kcal > 0 ? kcal : nil
    }

    private func selectChartDay(_ dayKey: String) {
        guard let date = MetricsRepository.parseLocalDay(dayKey) else { return }
        tabRouter.selectedDate = date
    }
}

// MARK: - Shared helpers

private func ringWeekChart(
    title: String,
    points: [WeeklyBarPoint],
    maxValue: Double,
    color: Color,
    format: @escaping (Double) -> String,
    onSelectDay: ((String) -> Void)? = nil
) -> some View {
    Group {
        if points.contains(where: { $0.value > 0 }) {
            WeeklyBarChart(
                title: title,
                points: points,
                maxValue: maxValue,
                barColor: color,
                formatValue: format,
                onSelectDay: onSelectDay
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
