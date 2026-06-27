import SwiftUI
import WhoopStore

// MARK: - HealthView
// "Salud" tab — health monitor (official WHOOP "Salud"): today's vitals + 7-day trends.

struct HealthView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var tabRouter: RootTabRouter

    @State private var baselines = BaselineCalculator.Averages()
    @State private var thirtyDayRows: [DailyMetric] = []
    @State private var weekPoints: [MetricKind: [TrendPoint]] = [:]
    @State private var selectedDayMetric: DailyMetric?

    private var selectedDate: Date { tabRouter.selectedDate }

    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var selectedDayLabel: String {
        TodayMetricHelpers.todayLabel(for: selectedDate, isViewingToday: isViewingToday)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                        ScreenHeader("Salud")
                        DayNavigator(selectedDate: $tabRouter.selectedDate, showsCalendarPicker: true)
                            .padding(.horizontal, WH.Spacing.md)
                            .padding(.top, -WH.Spacing.sm)

                        Text(isViewingToday
                             ? "Monitor de salud — valores de anoche y tendencia 7 días"
                             : "Monitor de salud — \(selectedDayLabel.lowercased()) y tendencia 7 días")
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                            .padding(.horizontal, WH.Spacing.md)
                            .padding(.top, -WH.Spacing.sm)

                        todayCard
                        trendSection

                        if metrics.isDemoPreviewActive {
                            demoBanner
                        }

                        Spacer(minLength: WH.Spacing.xl)
                    }
                    .padding(.bottom, WH.Spacing.md)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task {
            await metrics.refresh()
            await reloadData()
        }
        .refreshable {
            await metrics.refresh()
            await reloadData()
        }
        .onChange(of: metrics.lastRefreshedAt) { _ in
            Task { await reloadData() }
        }
        .onChange(of: tabRouter.selectedDate) { _ in
            Task { await reloadData() }
        }
    }

    private func reloadData() async {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: selectedDate)
        let from30 = cal.date(byAdding: .day, value: -30, to: anchor) ?? anchor
        let from7  = cal.date(byAdding: .day, value: -6, to: anchor) ?? anchor
        let dayKey = MetricsRepository.localDayString(for: anchor, calendar: cal)
        thirtyDayRows = await metrics.daily(
            fromDay: MetricsRepository.localDayString(for: from30, calendar: cal),
            toDay: dayKey
        )
        if isViewingToday {
            selectedDayMetric = metrics.today
        } else {
            selectedDayMetric = await metrics.dailyMetric(forDay: dayKey)
        }
        baselines = BaselineCalculator.thirtyDay(from: thirtyDayRows,
                                                 excludingDay: isViewingToday ? metrics.today?.day : dayKey)

        var points: [MetricKind: [TrendPoint]] = [:]
        let weekRows = thirtyDayRows.filter { row in
            guard let date = MetricsRepository.parseLocalDay(row.day, calendar: cal) else { return false }
            return date >= from7 && date <= anchor
        }
        for kind in MetricKind.healthSignalCases {
            let pts = weekRows.compactMap { row -> TrendPoint? in
                guard let val = kind.value(from: row),
                      val.isFinite,
                      let date = MetricsRepository.parseLocalDay(row.day, calendar: cal) else { return nil }
                return TrendPoint(id: row.day, date: date, value: val)
            }
            if pts.count >= 2 { points[kind] = pts }
        }
        weekPoints = points
    }

    // MARK: - Today values

    private var todayCard: some View {
        let d = isViewingToday ? (selectedDayMetric ?? metrics.today) : selectedDayMetric
        return DashboardCard {
            healthLink(kind: .hrv) {
                healthRow(icon: "waveform.path.ecg",
                          label: "VFC",
                          value: d?.avgHrv.map { String(format: "%.0f", $0) } ?? "—",
                          unit: d?.avgHrv != nil ? "ms" : nil,
                          accent: WH.Color.teal,
                          baseline: baselines.hrv,
                          current: d?.avgHrv)
            }
            DashboardDivider()
            healthLink(kind: .rhr) {
                healthRow(icon: "heart.fill",
                          label: "FC en reposo",
                          value: d?.restingHr.map { "\($0)" } ?? "—",
                          unit: d?.restingHr != nil ? "lpm" : nil,
                          accent: WH.Color.textPrimary,
                          baseline: baselines.rhr,
                          current: d?.restingHr.map(Double.init))
            }
            DashboardDivider()
            healthLink(kind: .spo2) {
                healthRow(icon: "lungs.fill",
                          label: "SpO₂",
                          value: d?.spo2Pct.map { String(format: "%.1f", $0) } ?? "—",
                          unit: d?.spo2Pct != nil ? "%" : nil,
                          accent: WH.Color.sleepBlue,
                          baseline: average30d { $0.spo2Pct },
                          current: d?.spo2Pct,
                          footnote: "Estimado · sin calibrar vs oxímetro")
            }
            DashboardDivider()
            healthLink(kind: .respRate) {
                healthRow(icon: "wind",
                          label: "Frecuencia respiratoria",
                          value: d?.respRateBpm.map { String(format: "%.1f", $0) } ?? "—",
                          unit: d?.respRateBpm != nil ? "rpm" : nil,
                          accent: WH.Color.textPrimary,
                          baseline: average30d { $0.respRateBpm },
                          current: d?.respRateBpm,
                          footnote: "Media nocturna")
            }
            DashboardDivider()
            healthLink(kind: .skinTempDev) {
                healthRow(icon: "thermometer.medium",
                          label: "Temperatura cutánea",
                          value: d?.skinTempDevC.map { String(format: "%+.2f", $0) } ?? "—",
                          unit: d?.skinTempDevC != nil ? "Δ°C" : nil,
                          accent: WH.Color.recoveryYellow,
                          baseline: average30d { $0.skinTempDevC },
                          current: d?.skinTempDevC,
                          footnote: "Desviación vs. baseline")
            }
        }
        .padding(.horizontal, WH.Spacing.md)
    }

    @ViewBuilder
    private func healthLink<Content: View>(kind: MetricKind, @ViewBuilder content: () -> Content) -> some View {
        if kind.supportsDetailView {
            NavigationLink(destination: MetricDetailView(kind: kind)) {
                content()
            }
            .buttonStyle(.plain)
        } else {
            content()
        }
    }

    // MARK: - 7-day trends

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("TENDENCIAS — 7 DÍAS")
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)
                .padding(.horizontal, WH.Spacing.md)

            if weekPoints.isEmpty {
                Text("Necesitas al menos 2 noches con datos para ver tendencias.")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                    .padding(.horizontal, WH.Spacing.md)
            } else {
                ForEach(MetricKind.healthSignalCases) { kind in
                    if let pts = weekPoints[kind], let latest = pts.last {
                        TrendChartCard(
                            kind: kind,
                            points: pts,
                            latestLabel: kind.formatShort(latest.value),
                            titleOverride: kind.localizedTitle,
                            onSelectDay: { _ in }
                        )
                        .padding(.horizontal, WH.Spacing.md)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func average30d(_ extract: (DailyMetric) -> Double?) -> Double? {
        let vals = thirtyDayRows.compactMap(extract)
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private func healthRow(icon: String,
                           label: String,
                           value: String,
                           unit: String?,
                           accent: Color,
                           baseline: Double?,
                           current: Double?,
                           footnote: String? = nil) -> some View {
        let delta: String? = {
            guard let current, let baseline else { return nil }
            let diff = current - baseline
            if abs(diff) < 0.05 { return "≈ media 30d" }
            let sign = diff > 0 ? "+" : ""
            if label.contains("Temperatura") {
                return String(format: "%@%.2f vs 30d", sign, diff)
            }
            return String(format: "%@%.0f vs 30d", sign, diff)
        }()

        return DashboardRow(
            icon: icon,
            label: label,
            value: value,
            unit: unit,
            baseline: delta ?? footnote,
            accentColor: accent,
            embedded: true,
            trend: trend(current, vs: baseline, tolerance: label.contains("FC") ? 2 : 0.5)
        )
    }

    private func trend(_ value: Double?, vs baseline: Double?, tolerance: Double) -> DashboardRow.Trend? {
        guard let value, let baseline else { return nil }
        if value > baseline + tolerance { return .up }
        if value < baseline - tolerance { return .down }
        return .flat
    }

    private var demoBanner: some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(WH.Color.sleepBlue)
            Text("Vista previa — señales de referencia")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
        .padding(WH.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.sleepBlue.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
        .padding(.horizontal, WH.Spacing.md)
    }
}

#Preview {
    HealthView()
        .environmentObject(MetricsRepository(deviceId: "preview"))
        .environmentObject(RootTabRouter())
}
