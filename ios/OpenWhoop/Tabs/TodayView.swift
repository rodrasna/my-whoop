import SwiftUI
import WhoopStore

// MARK: - TodayView
// The command-centre "Today" tab. Renders server-cached recovery/strain/sleep/HRV/RHR
// metrics pulled from MetricsRepository.
// Tapping any metric card → MetricDetailView (full history, range selector).

struct TodayView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var live: LiveViewModel

    @State private var weekRows: [DailyMetric] = []
    @State private var baselines = BaselineCalculator.Averages()
    @State private var sleepNights = 0
    @State private var ringDestination: RingDestination?
    @State private var showingAlarm = false

    // Alarm state (shared with the Sleep tab via UserDefaults) for the "tonight" card.
    @AppStorage(AlarmKeys.enabled)      private var alarmEnabled   = false
    @AppStorage(AlarmKeys.wakeByHour)   private var wakeByHour     = 7
    @AppStorage(AlarmKeys.wakeByMinute) private var wakeByMinute   = 0

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()

                Group {
                    if metrics.isRefreshing && metrics.today == nil && metrics.lastNight == nil {
                        loadingView
                    } else {
                        scrollContent
                    }
                }
            }
            // Hide the system nav bar on the root so the custom ScreenHeader sits tight
            // below the status bar/Dynamic Island. Pushed detail views manage their own bars.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAlarm) {
                AlarmView()
                    .environmentObject(live)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await metrics.refresh()
            await reloadWeek()
            await reloadBaselines()
        }
        .refreshable {
            await metrics.refresh()
            await reloadWeek()
            await reloadBaselines()
        }
        .onChange(of: metrics.lastRefreshedAt) { _ in
            Task {
                await reloadWeek()
                await reloadBaselines()
            }
        }
    }

    private func reloadBaselines() async {
        baselines = await metrics.thirtyDayBaselines()
        sleepNights = await metrics.sleepNightCount()
    }

    private func reloadWeek() async {
        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let from = cal.date(byAdding: .day, value: -6, to: today) ?? today
        weekRows = await metrics.daily(fromDay: fmt.string(from: from), toDay: fmt.string(from: today))
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: WH.Spacing.md) {
            ProgressView()
                .tint(WH.Color.textSecondary)
            Text("Cargando métricas…")
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
                ScreenHeader("Hoy")

                // Anillos Sueño · Recuperación · Esfuerzo (estilo WHOOP)
                TriRingHeader(sleepFraction: sleepFraction,
                              recoveryFraction: metrics.today?.recovery,
                              strain: metrics.today?.strain,
                              onSleepTap: { ringDestination = .sleep },
                              onRecoveryTap: { ringDestination = .recovery },
                              onStrainTap: { ringDestination = .strain })
                    .padding(.vertical, WH.Spacing.sm)

                if sleepNights < 4 && !metrics.isDemoPreviewActive {
                    CalibrationBanner(
                        completedNights: sleepNights,
                        title: "Calibrando tu recuperación"
                    )
                }

                if metrics.isServerConfigured && needsMorningSync && !metrics.isDemoPreviewActive {
                    morningSyncBanner
                }

                if metrics.isDemoPreviewActive {
                    demoPreviewBanner
                }

                miDiaSection

                sectionLabel("Mi panel de control")
                groupedDashboard

                if !weekRows.isEmpty || metrics.today?.strain != nil {
                    sectionLabel("Tendencias semanales")
                    weeklyTrendsSection
                }

                stressMonitorPlaceholder

                if let err = metrics.lastError {
                    errorBanner(err)
                }

                if metrics.today == nil && metrics.lastNight == nil && !metrics.isRefreshing {
                    emptyState
                }

                strapNote
                syncFooter

                Spacer(minLength: WH.Spacing.xl)
            }
            .padding(WH.Spacing.md)
        }
        .background(WH.Color.background)
        .background {
            Group {
                NavigationLink(destination: SleepRingDetailView(),
                               tag: RingDestination.sleep,
                               selection: $ringDestination) { EmptyView() }
                NavigationLink(destination: RecoveryRingDetailView(),
                               tag: RingDestination.recovery,
                               selection: $ringDestination) { EmptyView() }
                NavigationLink(destination: StrainRingDetailView(),
                               tag: RingDestination.strain,
                               selection: $ringDestination) { EmptyView() }
            }
            .hidden()
        }
    }

    /// True when server is up but last night has no sleep session yet.
    private var needsMorningSync: Bool {
        let noSleep = (metrics.today?.totalSleepMin ?? 0) <= 0
            && metrics.lastNight == nil
        let noRecovery = metrics.today?.recovery == nil
        return noSleep && noRecovery
    }

    private var demoPreviewBanner: some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(WH.Color.sleepBlue)
            Text("Vista previa — métricas de referencia WHOOP oficial (no del strap)")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
        .padding(WH.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.sleepBlue.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
    }

    private var morningSyncBanner: some View {
        HStack(alignment: .top, spacing: WH.Spacing.sm) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WH.Color.recoveryYellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("Sincroniza por la mañana")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                Text("El sueño aparece cuando abres OpenWhoop tras dormir, conectas el strap (Dispositivo) y dejas sincronizar. La app oficial no comparte datos con tu servidor.")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(WH.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.recoveryYellow.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(WH.Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - "Mi día" (actividad de anoche + sueño de esta noche, estilo WHOOP)

    private var miDiaSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionLabel("Mi día")
            actividadHoyCard
            suenoEstaNocheCard
        }
    }

    /// Tarjeta "Actividades de hoy" — fila de la sesión de sueño de anoche (datos reales).
    private var actividadHoyCard: some View {
        let s = metrics.lastNight
        return VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("ACTIVIDADES DE HOY")
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)

            if let s {
                let durMin = Double(s.endTs - s.startTs) / 60
                Button { ringDestination = .sleep } label: {
                    HStack(spacing: WH.Spacing.md) {
                        HStack(spacing: WH.Spacing.xs) {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text(formatSleepMinutes(durMin))
                                .font(.system(size: 15, weight: .bold, design: .default))
                                .fontWidth(.condensed)
                                .monospacedDigit()
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, WH.Spacing.sm)
                        .padding(.vertical, WH.Spacing.xs)
                        .background(WH.Color.sleepBlue,
                                    in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))

                        Text("SUEÑO")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(WH.Color.textPrimary)
                            .tracking(0.8)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(clockTime(s.startTs))
                            Text(clockTime(s.endTs))
                        }
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .fontWidth(.condensed)
                        .foregroundStyle(WH.Color.textSecondary)
                        .monospacedDigit()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
                    }
                    .padding(WH.Spacing.sm)
                    .background(WH.Color.surface2,
                                in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Text("Sin actividades registradas todavía")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
        .padding(WH.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    /// Tarjeta "El sueño de esta noche" — alarma (real) + hora de dormir recomendada
    /// (derivada de la alarma menos 8 h; solo se muestra cuando hay alarma activa).
    private var suenoEstaNocheCard: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.md) {
            Text("EL SUEÑO DE ESTA NOCHE")
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: WH.Spacing.xs) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(WH.Color.sleepPurple)
                        Text(recommendedBedtime ?? "—")
                            .font(.system(size: 22, weight: .bold, design: .default))
                            .fontWidth(.condensed)
                            .foregroundStyle(WH.Color.textPrimary)
                            .monospacedDigit()
                    }
                    Text("HORA DE DORMIR RECOMENDADA")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(0.8)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: WH.Spacing.xs) {
                        Image(systemName: alarmEnabled ? "alarm.fill" : "alarm")
                            .font(.system(size: 13))
                            .foregroundStyle(alarmEnabled ? WH.Color.recoveryYellow : WH.Color.textSecondary)
                        Text(alarmEnabled ? alarmTimeString : "DESACTIVADA")
                            .font(.system(size: alarmEnabled ? 22 : 15, weight: .bold, design: .default))
                            .fontWidth(.condensed)
                            .foregroundStyle(alarmEnabled ? WH.Color.textPrimary : WH.Color.recoveryYellow)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text("ALARMA")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(0.8)
                }
            }

            Button { showingAlarm = true } label: {
                HStack(spacing: WH.Spacing.xs) {
                    Image(systemName: "alarm")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Establecer alarma")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(WH.Color.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, WH.Spacing.sm)
                .background(WH.Color.surface2,
                            in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(WH.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    /// 24h "HH:mm" from an epoch timestamp.
    private func clockTime(_ epochSeconds: Int) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    /// Armed wake time as "HH:mm".
    private var alarmTimeString: String {
        String(format: "%02d:%02d", wakeByHour, wakeByMinute)
    }

    /// Recommended bedtime = alarm − 8h, only when an alarm is set.
    private var recommendedBedtime: String? {
        guard alarmEnabled else { return nil }
        var minutes = wakeByHour * 60 + wakeByMinute - 8 * 60
        minutes = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: - Dashboard (agrupado en una tarjeta, estilo WHOOP)

    private var groupedDashboard: some View {
        DashboardCard {
            NavigationLink(destination: MetricDetailView(kind: .recovery)) {
                recoveryRowEmbedded
            }
            .buttonStyle(.plain)
            DashboardDivider()
            NavigationLink(destination: MetricDetailView(kind: .strain)) {
                strainRowEmbedded
            }
            .buttonStyle(.plain)
            DashboardDivider()
            NavigationLink(destination: MetricDetailView(kind: .sleepDuration)) {
                sleepRowEmbedded
            }
            .buttonStyle(.plain)
            DashboardDivider()
            NavigationLink(destination: MetricDetailView(kind: .hrv)) {
                hrvRowEmbedded
            }
            .buttonStyle(.plain)
            DashboardDivider()
            NavigationLink(destination: MetricDetailView(kind: .rhr)) {
                rhrRowEmbedded
            }
            .buttonStyle(.plain)
        }
    }

    private var weeklyTrendsSection: some View {
        VStack(spacing: WH.Spacing.sm) {
            let strainPts = WeeklyChartBuilder.last7Days(from: weekRows) { $0.strain }
            if strainPts.contains(where: { $0.value > 0 }) {
                NavigationLink(destination: MetricDetailView(kind: .strain)) {
                    WeeklyBarChart(
                        title: "Esfuerzo",
                        points: strainPts,
                        maxValue: 21,
                        barColor: WH.Color.strainBlue,
                        formatValue: { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") }
                    )
                }
                .buttonStyle(.plain)
            }
            let recoveryPts = WeeklyChartBuilder.last7Days(from: weekRows) { m in
                m.recovery.map { $0 * 100 }
            }
            if recoveryPts.contains(where: { $0.value > 0 }) {
                NavigationLink(destination: MetricDetailView(kind: .recovery)) {
                    WeeklyBarChart(
                        title: "Recuperación",
                        points: recoveryPts,
                        maxValue: 100,
                        barColor: WH.Color.recoveryGreen,
                        formatValue: { "\(Int($0.rounded()))" }
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Dashboard rows (embedded en tarjeta única)

    /// Calificación del sueño (sesión) o eficiencia diaria; no mezclar con eficiencia 92% vs score 82%.
    private var sleepFraction: Double? {
        if let e = metrics.lastNight?.efficiency, e > 0 { return e }
        if let e = metrics.today?.efficiency, e > 0 { return e }
        if let m = metrics.today?.totalSleepMin, m > 0 { return min(1, m / 480) }
        return nil
    }

    private var stressMonitorPlaceholder: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            HStack {
                Text("MONITOR DE ESTRÉS")
                    .font(WH.Font.cardTitle)
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.2)
                Spacer()
                Text("Próximamente")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }
            RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous)
                .fill(WH.Color.surface)
                .frame(height: 88)
                .overlay {
                    HStack(spacing: WH.Spacing.md) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(WH.Color.stressLow.opacity(0.6))
                        Text("Requiere pipeline de HRV continuo — fase posterior")
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(WH.Spacing.md)
                }
            CalibrationBanner(
                completedNights: min(sleepNights, 4),
                requiredNights: 4,
                title: "Calibrando el monitor de estrés",
                footnote: "Usa OpenWhoop 4 noches para desbloquear el monitor de estrés"
            )
            .opacity(sleepNights < 4 ? 1 : 0.45)
        }
    }

    /// Up/down/flat vs 30-day baseline. `tolerance` is the dead-band (in the metric's units)
    /// under which the value counts as unchanged. Returns nil when either side is missing.
    private func trend(_ value: Double?, vs baseline: Double?, tolerance: Double) -> DashboardRow.Trend? {
        guard let value, let baseline else { return nil }
        if value > baseline + tolerance { return .up }
        if value < baseline - tolerance { return .down }
        return .flat
    }

    private var recoveryRowEmbedded: some View {
        let r = metrics.today?.recovery
        return DashboardRow(
            icon: "bolt.heart", label: "Recuperación",
            value: r.map { "\(Int(($0 * 100).rounded()))" } ?? "—",
            unit: r != nil ? "%" : nil,
            baseline: BaselineCalculator.formatBaseline(baselines.recoveryPct, decimals: 0),
            accentColor: r.map { WH.Color.recoveryColor(forPercent: $0 * 100) } ?? WH.Color.textSecondary,
            embedded: true,
            trend: trend(r.map { $0 * 100 }, vs: baselines.recoveryPct, tolerance: 2))
    }
    private var strainRowEmbedded: some View {
        let s = metrics.today?.strain
        return DashboardRow(
            icon: "figure.run", label: "Esfuerzo diario",
            value: s.map { String(format: "%.1f", $0) } ?? "—",
            unit: s != nil ? "/ 21" : nil,
            baseline: BaselineCalculator.formatBaseline(baselines.strain, decimals: 1),
            accentColor: s != nil ? WH.Color.strainBlue : WH.Color.textSecondary,
            embedded: true,
            trend: trend(s, vs: baselines.strain, tolerance: 0.5))
    }
    private var sleepRowEmbedded: some View { sleepRowBody(embedded: true) }
    private var hrvRowEmbedded: some View {
        let hrv = metrics.today?.avgHrv ?? metrics.lastNight?.avgHrv
        return DashboardRow(
            icon: "waveform.path.ecg", label: "Variabilidad FC",
            value: hrv.map { String(format: "%.0f", $0) } ?? "—",
            unit: hrv != nil ? "ms" : nil,
            baseline: BaselineCalculator.formatBaseline(baselines.hrv, decimals: 0),
            accentColor: hrv != nil ? WH.Color.recoveryGreen : WH.Color.textSecondary,
            embedded: true,
            trend: trend(hrv, vs: baselines.hrv, tolerance: 1))
    }
    private var rhrRowEmbedded: some View {
        let rhr = metrics.today?.restingHr ?? metrics.lastNight?.restingHr
        return DashboardRow(
            icon: "heart", label: "FC en reposo",
            value: rhr.map { "\($0)" } ?? "—",
            unit: rhr != nil ? "lpm" : nil,
            baseline: BaselineCalculator.formatBaseline(baselines.rhr, decimals: 0),
            accentColor: rhr != nil ? WH.Color.textPrimary : WH.Color.textSecondary,
            embedded: true,
            trend: trend(rhr.map(Double.init), vs: baselines.rhr, tolerance: 1))
    }

    private var recoveryRow: some View {
        let r = metrics.today?.recovery
        return DashboardRow(
            icon: "bolt.heart",
            label: "Recuperación",
            value: r.map { "\(Int(($0 * 100).rounded()))" } ?? "—",
            unit: r != nil ? "%" : nil,
            accentColor: r.map { WH.Color.recoveryColor(forPercent: $0 * 100) } ?? WH.Color.textSecondary)
    }

    private var strainRow: some View {
        let s = metrics.today?.strain
        return DashboardRow(
            icon: "figure.run",
            label: "Esfuerzo diario",
            value: s.map { String(format: "%.1f", $0) } ?? "—",
            unit: s != nil ? "/ 21" : nil,
            accentColor: s != nil ? WH.Color.strainBlue : WH.Color.textSecondary)
    }

    private var sleepRow: some View { sleepRowBody(embedded: false) }

    private func sleepRowBody(embedded: Bool) -> some View {
        let sleepMin: Double? = {
            if let m = metrics.today?.totalSleepMin, m > 0 { return m }
            if let s = metrics.lastNight {
                let d = Double(s.endTs - s.startTs) / 60
                return d > 0 ? d : nil
            }
            return nil
        }()
        let eff: Double? = {
            guard sleepMin != nil else { return nil }
            if let e = metrics.today?.efficiency, e > 0 { return e }
            if let e = metrics.lastNight?.efficiency, e > 0 { return e }
            return nil
        }()
        return DashboardRow(
            icon: "bed.double",
            label: "Anoche",
            value: sleepMin.map { formatSleepMinutes($0) } ?? "—",
            baseline: eff.map { "\(Int(($0 * 100).rounded()))% efic." },
            accentColor: sleepMin != nil ? WH.Color.textPrimary : WH.Color.textSecondary,
            embedded: embedded)
    }

    private var hrvRow: some View {
        let hrv = metrics.today?.avgHrv ?? metrics.lastNight?.avgHrv
        return DashboardRow(
            icon: "waveform.path.ecg",
            label: "Variabilidad FC",
            value: hrv.map { String(format: "%.0f", $0) } ?? "—",
            unit: hrv != nil ? "ms" : nil,
            accentColor: hrv != nil ? WH.Color.recoveryGreen : WH.Color.textSecondary)
    }

    private var rhrRow: some View {
        let rhr = metrics.today?.restingHr ?? metrics.lastNight?.restingHr
        return DashboardRow(
            icon: "heart",
            label: "FC en reposo",
            value: rhr.map { "\($0)" } ?? "—",
            unit: rhr != nil ? "lpm" : nil,
            accentColor: rhr != nil ? WH.Color.textPrimary : WH.Color.textSecondary)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: WH.Spacing.sm) {
                Image(systemName: metrics.isServerConfigured ? "arrow.triangle.2.circlepath" : "externaldrive.badge.xmark")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(WH.Color.textSecondary)
                if metrics.isServerConfigured {
                    Text("Sin métricas aún")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                    Text("Conecta el strap (Dispositivo), deja sincronizar y desliza hacia abajo para actualizar. La recuperación necesita ~4 noches.")
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

    // MARK: - Live strap status row (HR + battery when connected; caption when not)

    /// Compact pill showing a single live reading (HR or battery).
    private func liveChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: WH.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .fontWidth(.condensed)
                .foregroundStyle(WH.Color.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, WH.Spacing.sm)
        .padding(.vertical, WH.Spacing.xs)
        .background(WH.Color.surface2,
                    in: Capsule())
    }

    /// Shows live HR + battery pills when connected; otherwise shows the connect caption.
    private var strapNote: some View {
        Group {
            if live.state.connected, let hr = live.state.heartRate {
                HStack(spacing: WH.Spacing.sm) {
                    liveChip(icon: "heart.fill",
                             label: "\(hr) BPM LIVE",
                             color: WH.Color.recoveryRed)
                    if let bat = live.state.batteryPct {
                        let pct = Int(bat.rounded())
                        let batColor: Color = pct > 30 ? WH.Color.recoveryGreen
                                                       : WH.Color.recoveryYellow
                        let batIcon = pct > 70 ? "battery.100" :
                                      pct > 30 ? "battery.50"  : "battery.25"
                        liveChip(icon: batIcon,
                                 label: "\(pct)%",
                                 color: batColor)
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: WH.Spacing.xs) {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
                    Text("FC y batería en vivo cuando el strap está conectado (Dispositivo)")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Sync footer

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

    // MARK: - Error banner

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

    // MARK: - Formatting helpers

    private func formatSleepMinutes(_ totalMin: Double) -> String {
        guard totalMin > 0 else { return "—" }
        let hours = Int(totalMin) / 60
        let mins  = Int(totalMin) % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0              { return "\(hours)h" }
        return "\(mins)m"
    }

    private func relativeTime(from date: Date) -> String {
        let elapsed = Int(-date.timeIntervalSinceNow)
        switch elapsed {
        case ..<5:   return "ahora"
        case ..<60:  return "hace \(elapsed)s"
        case ..<3600:
            let m = elapsed / 60
            return "hace \(m)m"
        default:
            let h = elapsed / 3600
            return "hace \(h)h"
        }
    }
}

// MARK: - Preview

#Preview("Today — empty (cold start)") {
    TodayView()
        .environmentObject(MetricsRepository(deviceId: "preview"))
}

#Preview("Today — design gallery reference") {
    DesignGallery()
}
