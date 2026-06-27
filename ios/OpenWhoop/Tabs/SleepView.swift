import SwiftUI
import Charts
import WhoopStore

// MARK: - SleepView
// M2 Sleep tab — answers two questions at a glance:
//   (1) "How well did I sleep last night?"  → headline efficiency + duration + hypnogram
//   (2) "When have I been sleeping/waking over the past 7 nights?" → 7-night bar chart

struct SleepView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var live: LiveViewModel
    @EnvironmentObject private var tabRouter: RootTabRouter

    // Local async state
    @State private var detail: (session: CachedSleepSession, daily: DailyMetric?)?
    @State private var weekNights: [CachedSleepSession] = []
    @State private var naps: [CachedSleepSession] = []
    @State private var showingAlarm = false
    @State private var stageBaselines = BaselineCalculator.StagePercents()

    // Alarm state read from UserDefaults for the summary card.
    @AppStorage(AlarmKeys.enabled)    private var alarmEnabled   = false
    @AppStorage(AlarmKeys.wakeByHour) private var wakeByHour     = 7
    @AppStorage(AlarmKeys.wakeByMinute) private var wakeByMinute = 0

    // Static formatter — allocated once, reused across renders.
    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        fmt.amSymbol = "AM"
        fmt.pmSymbol = "PM"
        return fmt
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()

                Group {
                    if metrics.isRefreshing && detail == nil && weekNights.isEmpty {
                        loadingView
                    } else {
                        scrollContent
                    }
                }
            }
            // Hide the system nav bar on the root; pushed detail views manage their own bars.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAlarm) {
                // iOS 16: sheets don't reliably inherit environment objects — pass explicitly.
                AlarmView()
                    .environmentObject(live)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await metrics.refresh()
            await reloadLocal()
        }
        .refreshable {
            await metrics.refresh()
            await reloadLocal()
        }
        .onChange(of: metrics.lastRefreshedAt) { _ in
            Task { await reloadLocal() }
        }
        .onChange(of: tabRouter.selectedDate) { _ in
            Task { await reloadLocal() }
        }
    }

    // MARK: - Selected day

    private var selectedDate: Date { tabRouter.selectedDate }

    // MARK: - Data loading

    /// Reads the locally-cached derived data only. Must NOT call metrics.refresh(),
    /// or the lastRefreshedAt change it emits re-triggers onChange in an infinite loop.
    private func reloadLocal() async {
        detail = await metrics.sleepDetail(for: selectedDate)
        weekNights = await metrics.sevenNightSleepWake(nights: 7)
        let dayKey = MetricsRepository.localDayString(for: selectedDate)
        naps = await metrics.naps(endingOnDay: dayKey)
        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        let today = selectedDate
        let from = cal.date(byAdding: .day, value: -30, to: today) ?? today
        let rows = await metrics.daily(fromDay: fmt.string(from: from), toDay: fmt.string(from: today))
        stageBaselines = BaselineCalculator.stagePercents(from: rows)
    }

    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var selectedDayLabel: String {
        TodayMetricHelpers.todayLabel(for: selectedDate, isViewingToday: isViewingToday)
    }

    private var checkInEfficiencyPct: Double? {
        if let e = detail?.session.efficiency, e > 0 { return e * 100 }
        if let e = detail?.daily?.efficiency, e > 0 { return e * 100 }
        return nil
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: WH.Spacing.md) {
            ProgressView()
                .tint(WH.Color.textSecondary)
            Text("Cargando sueño…")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WH.Spacing.lg) {

                // Custom tight header (replaces the hidden system large-title nav bar)
                ScreenHeader("Sueño")
                DayNavigator(selectedDate: $tabRouter.selectedDate, showsCalendarPicker: true)
                    .padding(.bottom, WH.Spacing.xs)

                SleepCheckInCard(
                    dayKey: MetricsRepository.localDayString(for: selectedDate),
                    dayLabel: selectedDayLabel,
                    recoveryPct: detail?.daily?.recovery,
                    sleepEfficiencyPct: checkInEfficiencyPct
                )

                SleepCheckInCorrelationCard()

                // 1. Headline — efficiency hero + total duration
                headlineSection

                sleepQualityCard

                // 2. Hypnogram (noche principal)
                if let session = detail?.session {
                    HypnogramView(session: session)
                } else {
                    noDataCard(icon: "moon.zzz", message: "Sin etapas de sueño · \(selectedDayLabel)")
                }

                napsSection

                // 3. Stage breakdown + sleep stats
                stageBreakdownSection

                // 4. In-sleep signals
                inSleepSignalsSection

                // 5. 7-night sleep/wake chart
                sevenNightSection

                // 6. Smart alarm entry card
                alarmCard

                // Error banner (non-blocking)
                if let err = metrics.lastError {
                    errorBanner(err)
                }

                if metrics.isDemoPreviewActive {
                    HStack(spacing: WH.Spacing.xs) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(WH.Color.sleepBlue)
                        Text("Vista previa — datos de referencia")
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }

                // Empty state
                if detail == nil && !metrics.isRefreshing {
                    emptyState
                }

                // Freshness footer
                syncFooter

                Spacer(minLength: WH.Spacing.xl)
            }
            .padding(WH.Spacing.md)
        }
        .background(WH.Color.background)
    }

    // MARK: - 1. Headline section

    private var headlineSection: some View {
        let session = detail?.session
        let daily = detail?.daily

        let efficiencyPct: Double? = {
            if let e = session?.efficiency, e > 0 { return e * 100 }
            if let e = daily?.efficiency, e > 0 { return e * 100 }
            return nil
        }()

        return VStack(spacing: WH.Spacing.sm) {
            if let score = efficiencyPct {
                SleepPerformanceRing(scorePercent: score)
                    .frame(maxWidth: .infinity)
                    .padding(.top, WH.Spacing.sm)
                Text("Porcentaje de tiempo dormido vs. tiempo en cama (no es cómo te sientes).")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, WH.Spacing.sm)
            } else {
                Text("Sin datos de sueño · \(selectedDayLabel)")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WH.Spacing.xl)
            }

            if let session = session {
                Text("Noche · \(formatTime(session.startTs)) → \(formatTime(session.endTs))")
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .fontWidth(.condensed)
                    .foregroundStyle(WH.Color.textSecondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Sub-métricas de sueño (tarjeta bajo el anillo, estilo WHOOP)

    private var sleepQualityCard: some View {
        let session = detail?.session
        let daily = detail?.daily

        let efficiencyPct: Double? = {
            if let e = session?.efficiency, e > 0 { return e * 100 }
            if let e = daily?.efficiency, e > 0 { return e * 100 }
            return nil
        }()

        let asleepMin: Double? = {
            if let m = daily?.totalSleepMin, m > 0 { return m }
            if let s = session {
                let d = Double(s.endTs - s.startTs) / 60
                return d > 0 ? d : nil
            }
            return nil
        }()

        let needMin: Double = 480
        var rows: [SleepQualityMetricsCard.Row] = []

        if let eff = efficiencyPct {
            let band: String = {
                if eff >= 85 { return "Óptimo" }
                if eff >= 70 { return "Suficiente" }
                return "Deficiente"
            }()
            rows.append(.init(
                id: "efficiency",
                title: "Eficiencia del sueño",
                value: "\(Int(eff.rounded()))%",
                context: "Tiempo dormido vs. tiempo en cama · \(band)",
                gaugeValue: eff
            ))
        }

        if let slept = asleepMin {
            let pct = min(100, slept / needMin * 100)
            rows.append(.init(
                id: "hours",
                title: "Horas vs. lo necesario",
                value: "\(formatMinutes(slept)) / 8h",
                context: pct >= 100 ? "Cumples el objetivo de sueño" : "Faltan \(formatMinutes(max(0, needMin - slept))) para 8h",
                gaugeValue: pct
            ))
        }

        if let stats = SleepQualityBuilder.regularityStats(from: weekNights) {
            rows.append(.init(
                id: "regularity",
                title: "Consistencia horaria",
                value: "\(Int(stats.score.rounded()))%",
                context: SleepQualityBuilder.regularityContext(stats: stats),
                gaugeValue: stats.score
            ))
        }

        return SleepQualityMetricsCard(rows: rows)
    }

    // MARK: - 3. Stage breakdown + sleep stats

    private var stageBreakdownSection: some View {
        let session = detail?.session
        let daily = detail?.daily

        // Sleep latency: minutes from startTs to first non-wake stage
        let latencyMin: String = {
            guard let session = session,
                  let stages = parseStages(session.stagesJSON) else { return "—" }
            guard let firstNonWake = stages.first(where: { $0.stage != "wake" }) else { return "—" }
            let latency = (firstNonWake.start - Double(session.startTs)) / 60
            if latency < 0 { return "—" }
            return "\(Int(latency.rounded()))m"
        }()

        let timeInBed: String? = session.map {
            formatMinutes(Double($0.endTs - $0.startTs) / 60)
        }

        // Per-stage minutes: prefer the hypnogram stages (the same source the chart above
        // renders, so the bars and the % always agree); fall back to the server's daily
        // aggregates only when the session has no stage breakdown.
        let stageMinutes: (deep: Double?, rem: Double?, light: Double?, awake: Double?) = {
            if let session, let stages = parseStages(session.stagesJSON), !stages.isEmpty {
                var d = 0.0, r = 0.0, l = 0.0, w = 0.0
                for seg in stages {
                    let m = max(0, (seg.end - seg.start) / 60)
                    switch seg.stage {
                    case "deep":  d += m
                    case "rem":   r += m
                    case "light": l += m
                    default:      w += m
                    }
                }
                return (d, r, l, w)
            }
            return (daily?.deepMin, daily?.remMin, daily?.lightMin, nil)
        }()

        let deep  = stageMinutes.deep
        let rem   = stageMinutes.rem
        let light = stageMinutes.light
        let timeInBedMin: Double? = session.map { Double($0.endTs - $0.startTs) / 60 }
        let asleepMin = (deep ?? 0) + (rem ?? 0) + (light ?? 0)
        let awakeMin: Double? = {
            if let w = stageMinutes.awake { return w }
            guard let tib = timeInBedMin, tib > 0 else { return nil }
            return max(0, tib - asleepMin)
        }()
        // Sleep stages as % of time asleep (TST, AASM-style). Awake as % of time in bed.
        let sleepStageDenom = max(asleepMin, 1)
        let awakeDenom: Double = {
            let tib = timeInBedMin ?? (asleepMin + (awakeMin ?? 0))
            return max(tib, 1)
        }()

        return VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionHeader("Etapas del sueño")
            Text("\(selectedDayLabel.capitalized) vs. 30 días anteriores · % del tiempo dormido")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
            Text("Estimación con pulsera (sin EEG). Profundo y REM son aproximados; «Despierto» requiere movimiento + FC elevada ≥3 min para contar como perturbación.")
                .font(.system(size: 11))
                .foregroundStyle(WH.Color.textSecondary.opacity(0.85))

            VStack(spacing: WH.Spacing.md) {
                stageRow(label: "Despierto", color: WH.Color.stageWake, minutes: awakeMin,
                         totalMin: awakeDenom, typicalPct: stageBaselines.awake)
                stageRow(label: "Ligero", color: WH.Color.stageLight, minutes: light,
                         totalMin: sleepStageDenom, typicalPct: stageBaselines.light)
                stageRow(label: "Sueño profundo (SWS)", color: WH.Color.stageDeep, minutes: deep,
                         totalMin: sleepStageDenom, typicalPct: stageBaselines.deep)
                stageRow(label: "REM", color: WH.Color.stageRem, minutes: rem,
                         totalMin: sleepStageDenom, typicalPct: stageBaselines.rem)
            }
            .padding(WH.Spacing.md)
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))

            // Stats row
            HStack(spacing: WH.Spacing.sm) {
                smallStatTile(label: "TIEMPO EN CAMA", value: timeInBed ?? "—")
                smallStatTile(label: "PERTURBACIONES", value: daily?.disturbances.map { "\($0)" } ?? "—")
                smallStatTile(label: "LATENCIA", value: latencyMin)
            }
        }
    }

    /// One sleep-stage row, official-style: ringed dot + name + colored % pill + duration,
    /// with a proportional progress bar underneath.
    private func stageRow(label: String, color: Color, minutes: Double?,
                          totalMin: Double, typicalPct: Double?) -> some View {
        let frac: Double = (minutes != nil && totalMin > 0) ? min(1, minutes! / totalMin) : 0
        let pct: Int? = (minutes != nil && totalMin > 0) ? Int((frac * 100).rounded()) : nil
        return VStack(spacing: WH.Spacing.xs) {
            HStack(spacing: WH.Spacing.sm) {
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 13, height: 13)
                Text(label.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WH.Color.textPrimary)
                    .tracking(0.5)
                if let pct {
                    Text("\(pct)%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.18), in: Capsule())
                }
                Spacer()
                Text(minutes.map { formatMinutes($0) } ?? "—")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .fontWidth(.condensed)
                    .foregroundStyle(minutes != nil ? WH.Color.textPrimary : WH.Color.textSecondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    StripedBarBackground()
                        .clipShape(Capsule())
                        .frame(height: 8)
                    if let typical = typicalPct {
                        let lo = max(0, (typical - 8) / 100)
                        let hi = min(1, (typical + 8) / 100)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(WH.Color.textSecondary.opacity(0.55),
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .frame(width: geo.size.width * CGFloat(hi - lo), height: 12)
                            .offset(x: geo.size.width * CGFloat(lo), y: -2)
                    }
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, geo.size.width * CGFloat(frac)), height: 8)
                }
            }
            .frame(height: 12)
        }
    }

    private func smallStatTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            Text(label)
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.0)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(WH.Font.metricMedium(size: 20))
                .foregroundStyle(WH.Color.textPrimary)
                .monospacedDigit()
        }
        .padding(WH.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    // MARK: - 4. In-sleep signals
    // Note: SpO2, skin temp deviation, and respiratory rate are WHOOP-LIKE APPROXIMATIONS
    // derived from the optical + accelerometer sensors. They have not been clinically calibrated.

    private var inSleepSignalsSection: some View {
        let session = detail?.session
        let daily = detail?.daily

        return VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionHeader("Señales durante el sueño")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      spacing: WH.Spacing.sm) {

                // FC: única señal con serie temporal real → pulsable para ver la evolución.
                if let session {
                    NavigationLink(destination: SleepHRChartView(session: session)) {
                        MetricCard(
                            title: "FC en reposo",
                            value: session.restingHr.map { "\($0)" } ?? "—",
                            unit: session.restingHr != nil ? "lpm" : nil,
                            accentColor: session.restingHr != nil ? WH.Color.textPrimary : WH.Color.textSecondary
                        ) {
                            chartHint
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    MetricCard(
                        title: "FC en reposo",
                        value: "—",
                        unit: nil,
                        accentColor: WH.Color.textSecondary
                    )
                }

                MetricCard(
                    title: "VFC",
                    value: session?.avgHrv.map { String(format: "%.0f", $0) } ?? "—",
                    unit: session?.avgHrv != nil ? "ms" : nil,
                    accentColor: session?.avgHrv != nil ? WH.Color.recoveryGreen : WH.Color.textSecondary
                )

                // Respiración: tendencia por instante (RSA del IBI) → pulsable.
                if let session {
                    NavigationLink(destination: SleepRespChartView(session: session)) {
                        MetricCard(
                            title: "Frec. respiratoria",
                            value: daily?.respRateBpm.map { String(format: "%.1f", $0) } ?? "—",
                            unit: daily?.respRateBpm != nil ? "/min" : nil,
                            accentColor: daily?.respRateBpm != nil ? WH.Color.strainBlue : WH.Color.textSecondary
                        ) {
                            chartHint
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    MetricCard(
                        title: "Frec. respiratoria",
                        value: "—",
                        unit: nil,
                        accentColor: WH.Color.textSecondary
                    )
                }

                // SpO₂: tendencia por instante (ratio-of-ratios, con gate de calidad) → pulsable.
                if let session {
                    NavigationLink(destination: SleepSpo2ChartView(session: session)) {
                        MetricCard(
                            title: "SpO₂ estimada",
                            value: daily?.spo2Pct.map { String(format: "%.1f", $0) } ?? "—",
                            unit: daily?.spo2Pct != nil ? "%" : nil,
                            accentColor: daily?.spo2Pct != nil ? WH.Color.sleepBlue : WH.Color.textSecondary
                        ) {
                            chartHint
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    MetricCard(
                        title: "SpO₂ estimada",
                        value: daily?.spo2Pct.map { String(format: "%.1f", $0) } ?? "—",
                        unit: daily?.spo2Pct != nil ? "%" : nil,
                        accentColor: daily?.spo2Pct != nil ? WH.Color.sleepBlue : WH.Color.textSecondary
                    )
                }

                // Temperatura de piel: desviación respecto a mediana de la noche → pulsable.
                if let session {
                    NavigationLink(destination: SleepTempChartView(session: session)) {
                        MetricCard(
                            title: "Desv. temp. piel",
                            value: {
                                guard let t = daily?.skinTempDevC else { return "—" }
                                return String(format: "%+.1f", t)
                            }(),
                            unit: daily?.skinTempDevC != nil ? "Δ°C" : nil,
                            accentColor: daily?.skinTempDevC != nil ? WH.Color.recoveryYellow : WH.Color.textSecondary
                        ) {
                            chartHint
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    MetricCard(
                        title: "Desv. temp. piel",
                        value: "—",
                        unit: nil,
                        accentColor: WH.Color.textSecondary
                    )
                }
            }
        }
    }

    /// Small affordance shown inside the tappable FC card so the user knows it opens a chart.
    private var chartHint: some View {
        HStack(spacing: WH.Spacing.xs) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 10, weight: .semibold))
            Text("Ver evolución")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(WH.Color.textSecondary)
    }

    // MARK: - 5. 7-night sleep/wake chart

    private var sevenNightSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionHeader("Sueño / vigilia · 7 noches")

            if weekNights.count < 1 {
                noDataCard(icon: "chart.bar.xaxis", message: "Faltan noches para mostrar la tendencia")
            } else {
                SevenNightChart(sessions: weekNights)

                if weekNights.count < 2 {
                    Text("Registra más noches para ver la tendencia completa")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                        .padding(.top, WH.Spacing.xs)
                }
            }
        }
    }

    // MARK: - 6. Smart alarm card

    /// Tappable alarm entry card. Shows the armed wake time (or "No alarm set") and
    /// opens AlarmView on tap. Lives on the Sleep tab — WHOOP-style: you set your wake
    /// alarm where you see your sleep data.
    private var alarmCard: some View {
        Button {
            showingAlarm = true
        } label: {
            HStack(spacing: WH.Spacing.sm) {
                Image(systemName: alarmEnabled ? "alarm.fill" : "alarm")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(alarmEnabled ? WH.Color.sleepPurple : WH.Color.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        (alarmEnabled ? WH.Color.sleepPurple : WH.Color.textSecondary).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("ALARMA INTELIGENTE")
                        .font(WH.Font.cardTitle)
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(1.2)
                    if alarmEnabled {
                        Text("Despertar · \(alarmTimeString)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(WH.Color.textPrimary)
                    } else {
                        Text("Sin alarma configurada")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
            }
            .padding(WH.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Formats the stored hour + minute into "6:45 AM" style.
    private var alarmTimeString: String {
        var comps = DateComponents()
        comps.hour   = wakeByHour
        comps.minute = wakeByMinute
        guard let date = Calendar.current.date(from: comps) else {
            return "\(wakeByHour):\(String(format: "%02d", wakeByMinute))"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        fmt.amSymbol = "AM"
        fmt.pmSymbol = "PM"
        return fmt.string(from: date)
    }

    // MARK: - Helpers / sub-components

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(WH.Font.cardTitle)
            .foregroundStyle(WH.Color.textSecondary)
            .tracking(1.5)
            .padding(.top, WH.Spacing.xs)
    }

    private func noDataCard(icon: String, message: String) -> some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(WH.Color.textSecondary)
            Text(message)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
            Spacer()
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: WH.Spacing.sm) {
                Image(systemName: metrics.isServerConfigured ? "moon.zzz" : "externaldrive.badge.xmark")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(WH.Color.textSecondary)
                if metrics.isServerConfigured {
                    Text(isViewingToday ? "Sin sueño registrado" : "Sin sueño · \(selectedDayLabel)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                    Text("Por la mañana: cierra la app oficial, abre OpenWhoop → Dispositivo → conecta el strap y espera la sincronización. Luego desliza hacia abajo aquí.")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Servidor no configurado")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                    Text("Configura WHOOP_BASE_URL y WHOOP_API_KEY en Secrets.xcconfig y recompila.")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, WH.Spacing.xxl)
            .padding(.horizontal, WH.Spacing.md)
            Spacer()
        }
    }

    private var syncFooter: some View {
        HStack {
            if metrics.isRefreshing {
                HStack(spacing: WH.Spacing.xs) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(WH.Color.textSecondary)
                    Text("Actualizando…")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                }
            } else if let at = metrics.lastRefreshedAt {
                Text("Actualizado \(relativeTime(from: at))")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }
            Spacer()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WH.Color.recoveryYellow)
            Text(message)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(WH.Spacing.sm)
        .background(WH.Color.surface2,
                    in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
    }

    // MARK: - Siestas / descanso (no cuentan para recovery)

    private var napsSection: some View {
        Group {
            if !naps.isEmpty {
                VStack(alignment: .leading, spacing: WH.Spacing.sm) {
                    sectionHeader("Siestas y descanso")
                    Text("Reposo detectado en la pulsera. No alimenta recovery ni el anillo de la noche.")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                    ForEach(naps, id: \.startTs) { nap in
                        NapSessionCard(session: nap, formatTime: formatTime, formatMinutes: formatMinutes)
                    }
                }
            }
        }
    }

    // MARK: - Formatting helpers

    private func formatMinutes(_ totalMin: Double) -> String {
        guard totalMin > 0 else { return "—" }
        let hours = Int(totalMin) / 60
        let mins  = Int(totalMin) % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0              { return "\(hours)h" }
        return "\(mins)m"
    }

    private func formatTime(_ epochSeconds: Int) -> String {
        SleepView.timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    private func relativeTime(from date: Date) -> String {
        let elapsed = Int(-date.timeIntervalSinceNow)
        switch elapsed {
        case ..<5:   return "ahora mismo"
        case ..<60:  return "hace \(elapsed)s"
        case ..<3600:
            let m = elapsed / 60
            return "hace \(m)min"
        default:
            let h = elapsed / 3600
            return "hace \(h)h"
        }
    }
}

// MARK: - Nap session card

private struct NapSessionCard: View {
    let session: CachedSleepSession
    let formatTime: (Int) -> String
    let formatMinutes: (Double) -> String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: WH.Spacing.sm) {
                    Image(systemName: "powersleep")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(WH.Color.recoveryYellow)
                        .frame(width: 28, height: 28)
                        .background(WH.Color.recoveryYellow.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Siesta")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WH.Color.textPrimary)
                        Text("\(formatTime(session.startTs)) → \(formatTime(session.endTs)) · \(formatMinutes(Double(session.endTs - session.startTs) / 60))")
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                    Spacer()
                    if let eff = session.efficiency, eff > 0 {
                        Text("\(Int((eff * 100).rounded()))%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WH.Color.textSecondary.opacity(0.6))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                HypnogramView(session: session)
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }
}

// MARK: - Striped bar (fondo rayado estilo WHOOP)

private struct StripedBarBackground: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let step: CGFloat = 6
                var x: CGFloat = -geo.size.height
                while x < geo.size.width + geo.size.height {
                    path.move(to: CGPoint(x: x, y: geo.size.height))
                    path.addLine(to: CGPoint(x: x + geo.size.height, y: 0))
                    x += step
                }
            }
            .stroke(WH.Color.separator.opacity(0.45), lineWidth: 1)
            .background(WH.Color.ringTrack)
        }
    }
}

// MARK: - Preview

#Preview("Sleep — empty (cold start)") {
    SleepView()
        .environmentObject(MetricsRepository(deviceId: "preview"))
        .environmentObject(LiveViewModel())
}
