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
    @State private var sleepNights = 0
    @State private var ringDestination: RingDestination?
    @State private var showingAlarm = false
    @State private var showingDevice = false
    @StateObject private var strapTimer = StrapTimerController.shared
    @State private var selectedDate = Date()
    @State private var selectedDayMetric: DailyMetric?
    @State private var selectedNightSleep: CachedSleepSession?
    @State private var stressPoints: [StressPoint] = []

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
            .sheet(isPresented: $showingDevice) {
                NavigationStack {
                    LiveView()
                        .environmentObject(live)
                }
                .presentationDragIndicator(.visible)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await metrics.refresh()
            await reloadSelectedDay()
            await reloadWeek()
            await reloadSleepNights()
        }
        .refreshable {
            await metrics.refresh()
            await reloadSelectedDay()
            await reloadWeek()
            await reloadSleepNights()
        }
        .onChange(of: metrics.lastRefreshedAt) { _ in
            Task {
                await reloadSelectedDay()
                await reloadWeek()
                await reloadSleepNights()
            }
        }
        .onChange(of: selectedDate) { _ in
            Task {
                await reloadSelectedDay()
                await reloadWeek()
            }
        }
    }

    // MARK: - Selected day context

    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var dayMetric: DailyMetric? {
        isViewingToday ? metrics.today : selectedDayMetric
    }

    private var nightSleep: CachedSleepSession? {
        isViewingToday ? metrics.lastNight : selectedNightSleep
    }

    private func reloadSelectedDay() async {
        if isViewingToday {
            selectedDayMetric = nil
            selectedNightSleep = metrics.lastNight
        } else {
            let day = MetricsRepository.localDayString(for: selectedDate)
            selectedDayMetric = await metrics.dailyMetric(forDay: day)
            selectedNightSleep = await metrics.sleepSession(endingOnDay: day)
        }
        stressPoints = await metrics.stressPoints(for: selectedDate)
    }

    private func reloadSleepNights() async {
        sleepNights = await metrics.sleepNightCount()
    }

    private var yesterdayMetric: DailyMetric? {
        TodayMetricHelpers.dailyMetric(
            offset: -1,
            anchor: selectedDate,
            today: metrics.today,
            selected: selectedDayMetric,
            weekRows: weekRows,
            isViewingToday: isViewingToday
        )
    }

    private func reloadWeek() async {
        weekRows = await metrics.dailyLastDays(7, endingOn: selectedDate)
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

    private var recoveryDisplay: (fraction: Double, provisional: Bool)? {
        guard let r = TodayMetricHelpers.recoveryPercent(
            sleep: nightSleep, daily: dayMetric, sleepNights: sleepNights
        ) else { return nil }
        return (r.percent / 100.0, r.provisional)
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WH.Spacing.lg) {

                // Day navigator + strap status (official-style top chrome)
                TodayTopBar(selectedDate: $selectedDate,
                            liveState: live.state,
                            onDeviceTap: { showingDevice = true })

                // Anillos Sueño · Recuperación · Esfuerzo (estilo WHOOP)
                TriRingHeader(sleepFraction: sleepFraction,
                              recoveryFraction: recoveryDisplay?.fraction,
                              recoveryProvisional: recoveryDisplay?.provisional ?? false,
                              strain: dayMetric?.strain,
                              onSleepTap: { ringDestination = .sleep },
                              onRecoveryTap: { ringDestination = .recovery },
                              onStrainTap: { ringDestination = .strain })
                    .padding(.vertical, WH.Spacing.sm)

                if sleepNights < 4 && !metrics.isDemoPreviewActive {
                    CalibrationBanner(
                        completedNights: sleepNights,
                        title: "Calibrando tu recuperación",
                        footnote: recoveryDisplay != nil
                            ? "Recuperación visible pero provisional — con 4 noches usará tu baseline personal"
                            : nil
                    )
                }

                if metrics.isServerConfigured && needsMorningSync && !metrics.isDemoPreviewActive {
                    morningSyncBanner
                }

                if metrics.isDemoPreviewActive {
                    demoPreviewBanner
                }

                miDiaSection

                sectionLabel("Mi panel de control · \(TodayMetricHelpers.todayLabel(for: selectedDate, isViewingToday: isViewingToday))")
                groupedDashboard

                if !weekRows.isEmpty || dayMetric?.strain != nil {
                    sectionLabel("Tendencias semanales")
                    weeklyTrendsSection
                }

                stressMonitorPlaceholder

                if let err = metrics.lastError {
                    errorBanner(err)
                }

                if dayMetric == nil && nightSleep == nil && !metrics.isRefreshing {
                    emptyState
                }

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
        guard isViewingToday else { return false }
        let noSleep = (dayMetric?.totalSleepMin ?? 0) <= 0 && nightSleep == nil
        let noRecovery = dayMetric?.recovery == nil
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
            if isViewingToday {
                suenoEstaNocheCard
                StrapTimerCard(timer: strapTimer)
                    .environmentObject(live)
            }
        }
    }

    /// Tarjeta "Actividades de hoy" — fila de la sesión de sueño de anoche (datos reales).
    private var actividadHoyCard: some View {
        let s = nightSleep
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
            let activityPts = WeeklyChartBuilder.last7Days(from: weekRows) {
                $0.exerciseCount.map { Double($0) }
            }
            if activityPts.contains(where: { $0.value > 0 }) {
                NavigationLink(destination: WorkoutsView()) {
                    WeeklyBarChart(
                        title: "Actividades",
                        points: activityPts,
                        barColor: WH.Color.strainBlue,
                        formatValue: { "\(Int($0.rounded()))" }
                    )
                }
                .buttonStyle(.plain)
            }
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
        if let e = nightSleep?.efficiency, e > 0 { return e }
        if let e = dayMetric?.efficiency, e > 0 { return e }
        if let m = dayMetric?.totalSleepMin, m > 0 { return min(1, m / 480) }
        return nil
    }

    private var stressMonitorPlaceholder: some View {
        StressMonitorCard(
            completedNights: sleepNights,
            sleepStartTs: nightSleep?.startTs,
            sleepEndTs: nightSleep?.endTs,
            points: stressPoints
        )
    }

    /// Up/down/flat vs ayer. Returns nil when either side is missing.
    private func trend(_ value: Double?, vs comparison: Double?, tolerance: Double) -> DashboardRow.Trend? {
        guard let value, let comparison else { return nil }
        if value > comparison + tolerance { return .up }
        if value < comparison - tolerance { return .down }
        return .flat
    }

    private var recoveryRowEmbedded: some View {
        let r = recoveryDisplay?.fraction ?? dayMetric?.recovery
        let provisional = recoveryDisplay?.provisional ?? false
        let y = yesterdayMetric?.recovery
        return DashboardRow(
            icon: "bolt.heart", label: "Recuperación",
            value: r.map { "\(Int(($0 * 100).rounded()))" } ?? "—",
            unit: r != nil ? "%" : nil,
            baseline: provisional
                ? "provisional · calibrando"
                : TodayMetricHelpers.yesterdayComparison(
                    current: r.map { $0 * 100 }, yesterday: y.map { $0 * 100 }, decimals: 0, unit: "%"),
            accentColor: r.map {
                provisional ? WH.Color.calibrationAccent : WH.Color.recoveryColor(forPercent: $0 * 100)
            } ?? WH.Color.textSecondary,
            embedded: true,
            trend: provisional ? nil : trend(r.map { $0 * 100 }, vs: y.map { $0 * 100 }, tolerance: 2))
    }
    private var strainRowEmbedded: some View {
        let s = dayMetric?.strain
        let y = yesterdayMetric?.strain
        return DashboardRow(
            icon: "figure.run", label: "Esfuerzo diario",
            value: s.map { String(format: "%.1f", $0) } ?? "—",
            unit: s != nil ? "/ 21" : nil,
            baseline: TodayMetricHelpers.yesterdayComparison(current: s, yesterday: y, decimals: 1),
            accentColor: s != nil ? WH.Color.strainBlue : WH.Color.textSecondary,
            embedded: true,
            trend: trend(s, vs: y, tolerance: 0.5))
    }
    private var sleepRowEmbedded: some View { sleepRowBody(embedded: true) }
    private var hrvRowEmbedded: some View {
        let hrv = TodayMetricHelpers.hrvMs(sleep: nightSleep, daily: dayMetric)
        let yHrv = TodayMetricHelpers.hrvMs(
            sleep: nil,
            daily: yesterdayMetric
        )
        return DashboardRow(
            icon: "waveform.path.ecg", label: "Variabilidad FC",
            value: hrv.map { String(format: "%.0f", $0) } ?? "—",
            unit: hrv != nil ? "ms" : nil,
            baseline: TodayMetricHelpers.sleepWindowLabel(sleep: nightSleep)
                ?? TodayMetricHelpers.yesterdayComparison(current: hrv, yesterday: yHrv, decimals: 0, unit: "ms"),
            accentColor: hrv != nil ? WH.Color.recoveryGreen : WH.Color.textSecondary,
            embedded: true,
            trend: trend(hrv, vs: yHrv, tolerance: 1))
    }
    private var rhrRowEmbedded: some View {
        let rhr = TodayMetricHelpers.restingHr(sleep: nightSleep, daily: dayMetric)
        let yRhr = TodayMetricHelpers.restingHr(sleep: nil, daily: yesterdayMetric).map(Double.init)
        return DashboardRow(
            icon: "heart", label: "FC en reposo",
            value: rhr.map { "\($0)" } ?? "—",
            unit: rhr != nil ? "lpm" : nil,
            baseline: TodayMetricHelpers.sleepWindowLabel(sleep: nightSleep)
                ?? TodayMetricHelpers.yesterdayComparison(
                    current: rhr.map(Double.init), yesterday: yRhr, decimals: 0, unit: "lpm"),
            accentColor: rhr != nil ? WH.Color.textPrimary : WH.Color.textSecondary,
            embedded: true,
            trend: trend(rhr.map(Double.init), vs: yRhr, tolerance: 1))
    }

    private var recoveryRow: some View {
        let r = dayMetric?.recovery
        return DashboardRow(
            icon: "bolt.heart",
            label: "Recuperación",
            value: r.map { "\(Int(($0 * 100).rounded()))" } ?? "—",
            unit: r != nil ? "%" : nil,
            accentColor: r.map { WH.Color.recoveryColor(forPercent: $0 * 100) } ?? WH.Color.textSecondary)
    }

    private var strainRow: some View {
        let s = dayMetric?.strain
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
            if let m = dayMetric?.totalSleepMin, m > 0 { return m }
            if let s = nightSleep {
                let d = Double(s.endTs - s.startTs) / 60
                return d > 0 ? d : nil
            }
            return nil
        }()
        let eff: Double? = {
            guard sleepMin != nil else { return nil }
            if let e = dayMetric?.efficiency, e > 0 { return e }
            if let e = nightSleep?.efficiency, e > 0 { return e }
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
        let hrv = TodayMetricHelpers.hrvMs(sleep: nightSleep, daily: dayMetric)
        return DashboardRow(
            icon: "waveform.path.ecg",
            label: "Variabilidad FC",
            value: hrv.map { String(format: "%.0f", $0) } ?? "—",
            unit: hrv != nil ? "ms" : nil,
            accentColor: hrv != nil ? WH.Color.recoveryGreen : WH.Color.textSecondary)
    }

    private var rhrRow: some View {
        let rhr = TodayMetricHelpers.restingHr(sleep: nightSleep, daily: dayMetric)
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
                    Text("Toca el icono del strap arriba a la derecha, deja sincronizar y desliza hacia abajo. La recuperación necesita ~4 noches.")
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
