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
    @State private var baselines = BaselineCalculator.Averages()

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
                        SleepPerformanceRing(scorePercent: score)
                            .padding(.top, WH.Spacing.md)
                    } else {
                        placeholderRing(label: "Sin datos de sueño")
                    }

                    if metrics.isDemoPreviewActive {
                        previewChip
                    }

                    if let detail {
                        sleepMetricsCard(session: detail.session, daily: detail.daily)
                    }

                    NavigationLink(destination: MetricDetailView(kind: .sleepDuration)) {
                        detailLinkRow(title: "Historial de sueño", icon: "chart.bar")
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
        baselines = await metrics.thirtyDayBaselines()
    }

    private func sleepMetricsCard(session: CachedSleepSession, daily: DailyMetric?) -> some View {
        DashboardCard {
            metricRow(label: "Tiempo dormido",
                      value: formatMinutes(daily?.totalSleepMin ?? Double(session.endTs - session.startTs) / 60),
                      baseline: BaselineCalculator.formatBaseline(baselines.sleepMin, decimals: 0))
            DashboardDivider()
            metricRow(label: "Eficiencia",
                      value: daily?.efficiency.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                      baseline: nil)
            DashboardDivider()
            metricRow(label: "VFC",
                      value: (daily?.avgHrv ?? session.avgHrv).map { String(format: "%.0f ms", $0) } ?? "—",
                      baseline: BaselineCalculator.formatBaseline(baselines.hrv, decimals: 0, unit: "ms"))
            DashboardDivider()
            metricRow(label: "FC en reposo",
                      value: (daily?.restingHr ?? session.restingHr).map { "\($0) lpm" } ?? "—",
                      baseline: BaselineCalculator.formatBaseline(baselines.rhr, decimals: 0, unit: "lpm"))
        }
    }
}

// MARK: - RecoveryRingDetailView

struct RecoveryRingDetailView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @State private var baselines = BaselineCalculator.Averages()
    @State private var nightCount = 0

    private var recoveryPct: Double? {
        metrics.today?.recovery.map { $0 * 100 }
    }

    var body: some View {
        ZStack {
            WH.Color.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: WH.Spacing.lg) {
                    if let pct = recoveryPct {
                        RecoveryRing(percent: pct, size: 220)
                            .padding(.top, WH.Spacing.md)
                    } else {
                        placeholderRing(label: "Sin recuperación aún")
                    }

                    if nightCount < 4 {
                        CalibrationBanner(
                            completedNights: nightCount,
                            title: "Calibrando tu recuperación",
                            footnote: "La recuperación necesita ~4 noches con el strap. Llevas \(nightCount)."
                        )
                    }

                    if metrics.isDemoPreviewActive { previewChip }

                    DashboardCard {
                        metricRow(label: "VFC",
                                  value: hrvValue,
                                  baseline: BaselineCalculator.formatBaseline(baselines.hrv, decimals: 0, unit: "ms"))
                        DashboardDivider()
                        metricRow(label: "FC en reposo",
                                  value: rhrValue,
                                  baseline: BaselineCalculator.formatBaseline(baselines.rhr, decimals: 0, unit: "lpm"))
                        DashboardDivider()
                        metricRow(label: "SpO2",
                                  value: metrics.today?.spo2Pct.map { String(format: "%.0f%%", $0) } ?? "—",
                                  baseline: nil)
                        DashboardDivider()
                        metricRow(label: "Respiración",
                                  value: metrics.today?.respRateBpm.map { String(format: "%.1f rpm", $0) } ?? "—",
                                  baseline: nil)
                    }

                    NavigationLink(destination: MetricDetailView(kind: .recovery)) {
                        detailLinkRow(title: "Historial de recuperación", icon: "chart.line.uptrend.xyaxis")
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
        let h = metrics.today?.avgHrv ?? metrics.lastNight?.avgHrv
        return h.map { String(format: "%.0f ms", $0) } ?? "—"
    }

    private var rhrValue: String {
        let r = metrics.today?.restingHr ?? metrics.lastNight?.restingHr
        return r.map { "\($0) lpm" } ?? "—"
    }

    private func load() async {
        baselines = await metrics.thirtyDayBaselines()
        nightCount = await metrics.sleepNightCount()
    }
}

// MARK: - StrainRingDetailView

struct StrainRingDetailView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @State private var baselines = BaselineCalculator.Averages()

    private var strain: Double? { metrics.today?.strain }

    var body: some View {
        ZStack {
            WH.Color.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: WH.Spacing.lg) {
                    if let s = strain {
                        StrainRing(strain: s)
                            .padding(.top, WH.Spacing.md)
                    } else {
                        placeholderRing(label: "Sin esfuerzo registrado")
                    }

                    if metrics.isDemoPreviewActive { previewChip }

                    DashboardCard {
                        metricRow(label: "Esfuerzo máx. día",
                                  value: strain.map { String(format: "%.1f / 21", $0) } ?? "—",
                                  baseline: BaselineCalculator.formatBaseline(baselines.strain, decimals: 1))
                        DashboardDivider()
                        metricRow(label: "Zonas FC 1–3", value: "—", baseline: "Próximamente")
                        DashboardDivider()
                        metricRow(label: "Zonas FC 4–5", value: "—", baseline: "Próximamente")
                        DashboardDivider()
                        metricRow(label: "Calorías", value: "—", baseline: "Próximamente")
                    }

                    NavigationLink(destination: MetricDetailView(kind: .strain)) {
                        detailLinkRow(title: "Historial de esfuerzo", icon: "chart.bar.fill")
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
        .task { baselines = await metrics.thirtyDayBaselines() }
    }
}

// MARK: - Shared helpers

private func placeholderRing(label: String) -> some View {
    ZStack {
        Circle()
            .stroke(WH.Color.ringTrack, lineWidth: 16)
            .frame(width: 220, height: 220)
        Text(label)
            .font(WH.Font.caption)
            .foregroundStyle(WH.Color.textSecondary)
            .multilineTextAlignment(.center)
            .padding()
    }
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

private func metricRow(label: String, value: String, baseline: String?) -> some View {
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
            if let baseline {
                Text("media 30d: \(baseline)")
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

private func formatMinutes(_ totalMin: Double) -> String {
    guard totalMin > 0 else { return "—" }
    let hours = Int(totalMin) / 60
    let mins = Int(totalMin) % 60
    if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
    if hours > 0 { return "\(hours)h" }
    return "\(mins)m"
}
