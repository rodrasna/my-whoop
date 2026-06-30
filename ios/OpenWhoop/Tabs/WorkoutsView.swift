import SwiftUI
import WhoopStore

// MARK: - WorkoutsView (pestaña Actividad)
// Pantalla de Esfuerzo al estilo WHOOP: anillo de strain del día arriba, acceso destacado a
// CrossFit, tendencia semanal de esfuerzo, y la lista de entrenos auto-detectados debajo.
// Los datos derivados vienen del servidor; las etiquetas de actividad se guardan en local.

enum ActivityRoute: Hashable { case crossfit, suggestDemo }

struct WorkoutsView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var dayPlanStore: WorkoutDayPlanStore
    @EnvironmentObject private var tabRouter: RootTabRouter
    @StateObject private var labelStore = ActivityLabelStore()
    @StateObject private var programStore = PRVNProgramStore.shared
    @State private var showProgramImport = false
    @State private var showDayEditor = false
    @State private var pickerWorkout: Workout?

    // MARK: - State

    @State private var workouts: [Workout] = []
    @State private var weekRows: [DailyMetric] = []
    @State private var strainChartRows: [DailyMetric] = []
    @State private var selectedDayMetric: DailyMetric?
    @State private var collapsedSections: Set<DayActivitySection> = [.hrSignals]
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var path: [ActivityRoute] = []
    @State private var sleepNights = 0
    @State private var coachReport: TrainingDayCoachReport?
    @State private var coachNarrative: String?
    @State private var coachLoading = false

    private let strainChartDayCount = 28

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                if isLoading {
                    loadingView
                } else {
                    listContent
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ActivityRoute.self) { route in
                switch route {
                case .crossfit:
                    CrossFitView(workouts: workouts, labelStore: labelStore)
                case .suggestDemo:
                    if let w = workouts.first {
                        WorkoutDetailView(workout: w, labelStore: labelStore, allWorkouts: workouts)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await reload()
            // Screenshot helper: -deepLink crossfit abre la pantalla CrossFit al arrancar.
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "-deepLink"), i + 1 < args.count {
                switch args[i + 1] {
                case "crossfit":
                    path = [.crossfit]
                case "suggest":
                    // Verificación: siembra muestras de referencia y abre un entreno sin clasificar.
                    labelStore.seedSamples(DemoDataLoader.demoCrossfitSamples())
                    path = [.suggestDemo]
                default:
                    break
                }
            }
        }
        .refreshable { await reload() }
        .sheet(isPresented: $showProgramImport) {
            PRVNProgramImportView(store: programStore)
        }
        .sheet(isPresented: $showDayEditor) {
            DayWorkoutEditorView(
                dayKey: selectedDayKey,
                selectedDate: selectedDate,
                workouts: selectedDayActivities,
                labelStore: labelStore,
                dayPlanStore: dayPlanStore,
                programStore: programStore,
                prvnDay: programStore.program(for: selectedDate),
                isTrainingBout: isTrainingBout
            )
        }
        .onChange(of: showDayEditor) { open in
            if !open {
                Task { await reloadCoachReport(recompute: true) }
            }
        }
        .sheet(item: $pickerWorkout) { workout in
            ActivityPickerView(workout: workout, labelStore: labelStore)
        }
        .onChange(of: tabRouter.selectedDate) { _ in
            collapsedSections = [.hrSignals]
            Task {
                await reloadWeekRows()
                await reloadSelectedDay()
                await reloadCoachReport()
            }
        }
    }

    private var selectedDate: Date { tabRouter.selectedDate }

    // MARK: - Coach analysis

    @ViewBuilder
    private var coachAnalysisSection: some View {
        if metrics.isServerConfigured, resolvedDayWorkout.primary != nil {
            if let report = coachReport {
                TrainingCoachCard(
                    report: report,
                    isLoading: coachLoading,
                    narrative: coachNarrative
                )
            } else if coachLoading {
                TrainingCoachCard(
                    report: TrainingDayCoachReport(
                        day: selectedDayKey,
                        style: nil,
                        activityType: nil,
                        primaryWorkoutId: nil,
                        summary: TrainingCoachSummary(
                            strainVsBaselinePct: nil,
                            avgHrVsBaselinePct: nil,
                            z4plusVsBaselinePct: nil,
                            verdict: "typical",
                            recoveryPct: nil,
                            baselineSessionCount: nil
                        ),
                        blocks: [],
                        insights: [],
                        dataQuality: "good",
                        inferredPlan: true,
                        trainingContext: nil
                    ),
                    isLoading: true
                )
            }
        }
    }

    private func reloadCoachReport(recompute: Bool = false) async {
        guard metrics.isServerConfigured else {
            coachReport = nil
            return
        }
        guard resolvedDayWorkout.primary != nil else {
            coachReport = nil
            return
        }
        coachLoading = true
        coachReport = await metrics.coachReport(forDay: selectedDayKey, recompute: recompute)
        if coachReport != nil, CoachLLMSettings.isEnabled {
            coachNarrative = await metrics.coachNarrative(forDay: selectedDayKey)?.narrative
        } else {
            coachNarrative = nil
        }
        coachLoading = false
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: WH.Spacing.md) {
            ProgressView().tint(WH.Color.textSecondary)
            Text("Cargando actividad…")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private var listContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WH.Spacing.lg) {
                VStack(alignment: .leading, spacing: WH.Spacing.xs) {
                    Text("ACTIVIDAD")
                        .font(WH.Font.cardTitle)
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(1.2)
                    DayNavigator(selectedDate: $tabRouter.selectedDate, showsCalendarPicker: true)
                }
                .padding(.horizontal, WH.Spacing.md)

                if let err = errorMessage {
                    errorBanner(err).padding(.horizontal, WH.Spacing.md)
                }

                strainRingSection
                if let recommendation = activityRecommendation {
                    ActivityRecommendationCard(recommendation: recommendation)
                }
                workoutsSection

                PRVNTodayProgramCard(
                    store: programStore,
                    date: selectedDate,
                    recoveryPercent: recoveryPercentForSelectedDay,
                    syncError: metrics.lastPRVNSyncError,
                    onImport: { showProgramImport = true }
                )
                .padding(.horizontal, WH.Spacing.md)
                sportInsightsCard
                crossFitCard
                coachAnalysisSection

                if !strainChartRows.isEmpty || selectedDayStrain != nil {
                    WeeklyBarChart(
                        title: "Esfuerzo",
                        points: WeeklyChartBuilder.lastNDays(
                            strainChartDayCount,
                            from: strainChartRows,
                            endingOn: Date(),
                            highlightDayKey: selectedDayKey,
                            value: { $0.strain }
                        ),
                        maxValue: 21,
                        barColor: WH.Color.strainBlue,
                        formatValue: { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") },
                        onSelectDay: { dayKey in
                            guard let date = MetricsRepository.parseLocalDay(dayKey) else { return }
                            tabRouter.selectedDate = date
                        },
                        isScrollable: true
                    )
                    .padding(.horizontal, WH.Spacing.md)
                }
            }
            .padding(.bottom, WH.Spacing.xl)
        }
        .background(WH.Color.background)
    }

    // MARK: - Strain ring (esfuerzo del día)

    private var strainRingSection: some View {
        VStack(spacing: WH.Spacing.sm) {
            StrainRing(strain: selectedDayStrain ?? 0, size: WH.Ring.detailHeroDiameter)
                .opacity(selectedDayStrain == nil ? 0.45 : 1)
            if selectedDayStrain == nil {
                Text(isViewingToday ? "Esfuerzo de hoy aún sin calcular" : "Sin esfuerzo calculado este día")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            } else {
                if let summary = strainActivitySummary {
                    Text(summary)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                        .multilineTextAlignment(.center)
                }
                Text("Calculado por FC y tiempo en zona — el tipo de actividad que etiquetes no cambia el strain.")
                    .font(.system(size: 11))
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, WH.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, WH.Spacing.sm)
    }

    private var strainActivitySummary: String? {
        let local = selectedDayActivities.count
        let server = serverExerciseCount(for: selectedDayKey) ?? 0
        let train = selectedDayActivities.filter(isTrainingBout).count
        if local > 0 {
            if train > 0 {
                return "\(local) actividad\(local == 1 ? "" : "es") · \(train) entreno\(train == 1 ? "" : "s")"
            }
            return "\(local) actividad\(local == 1 ? "" : "es") detectada\(local == 1 ? "" : "s")"
        }
        if server > 0 {
            return "\(server) actividad\(server == 1 ? "" : "es") en el servidor — desliza para cargar"
        }
        if selectedDayStrain != nil {
            return "Esfuerzo acumulado — sin actividades listadas aún"
        }
        return nil
    }

    private func serverExerciseCount(for dayKey: String) -> Int? {
        if isViewingToday, metrics.today?.day == dayKey, let c = metrics.today?.exerciseCount {
            return c
        }
        if selectedDayMetric?.day == dayKey, let c = selectedDayMetric?.exerciseCount {
            return c
        }
        if let c = weekRows.first(where: { $0.day == dayKey })?.exerciseCount {
            return c
        }
        return strainChartRows.first(where: { $0.day == dayKey })?.exerciseCount
    }

    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var selectedDayKey: String {
        MetricsRepository.localDayString(for: selectedDate)
    }

    private var resolvedDayWorkout: ResolvedDayWorkout {
        trainingContext.resolved
    }

    private var trainingContext: DayTrainingContext {
        dayPlanStore.trainingContext(
            dayKey: selectedDayKey,
            calendarDate: selectedDate,
            workouts: selectedDayActivities,
            labelStore: labelStore,
            prvnStore: programStore,
            isTrainingBout: isTrainingBout
        )
    }

    // MARK: - Sport insights (semana actual)

    private var sportInsightsCard: some View {
        let dayWorkouts = selectedDayActivities.filter(isTrainingBout)
        let dayStrain = selectedDayStrain
        let totalKcal = selectedDayActivities.compactMap(\.caloriesKcal).reduce(0, +)
        let unreviewed = selectedDayActivities.filter {
            !isTrainingBout($0) && !labelStore.isDismissed($0.id)
        }.count
        let peak = selectedDayActivities.max { ($0.strain ?? 0) < ($1.strain ?? 0) }

        return VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("RESUMEN DEL DÍA")
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)
                .padding(.horizontal, WH.Spacing.md)

            VStack(spacing: WH.Spacing.md) {
                HStack(spacing: WH.Spacing.lg) {
                    insightStat(value: "\(selectedDayActivities.count)",
                                unit: selectedDayActivities.count == 1 ? "actividad" : "actividades",
                                label: "DETECTADAS")
                    insightStat(value: "\(dayWorkouts.count)",
                                unit: dayWorkouts.count == 1 ? "entreno" : "entrenos",
                                label: "ENTRENOS")
                    insightStat(
                        value: dayStrain.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") } ?? "—",
                        unit: dayStrain != nil ? "strain" : nil,
                        label: "ESFUERZO"
                    )
                    insightStat(
                        value: totalKcal > 0 ? "\(Int(totalKcal.rounded()))" : "—",
                        unit: totalKcal > 0 ? "kcal" : nil,
                        label: "CALORÍAS"
                    )
                }

                if let peak, let strain = peak.strain {
                    HStack(spacing: WH.Spacing.sm) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(WH.Color.strainBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mayor esfuerzo del día")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(WH.Color.textPrimary)
                            Text("\(rowTime(peak.startTs)) · strain \(String(format: "%.1f", strain).replacingOccurrences(of: ".", with: ",")) · \(peak.durationS / 60) min")
                                .font(WH.Font.caption)
                                .foregroundStyle(WH.Color.textSecondary)
                        }
                        Spacer()
                    }
                }

                if unreviewed > 0 {
                    HStack(spacing: WH.Spacing.xs) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 12))
                            .foregroundStyle(WH.Color.recoveryYellow)
                        Text("\(unreviewed) sin revisar — desliza y toca Clasificar")
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(WH.Spacing.md)
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            .padding(.horizontal, WH.Spacing.md)
        }
    }

    private func insightStat(value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(WH.Font.metricMedium(size: 24))
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - CrossFit hero card

    private var crossFitCard: some View {
        let cf = workouts.filter { labelStore.effectiveType(for: $0) == .crossfit }
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekCount = cf.filter { Date(timeIntervalSince1970: TimeInterval($0.startTs)) >= weekStart }.count
        let last = cf.max(by: { $0.startTs < $1.startTs })

        return NavigationLink(value: ActivityRoute.crossfit) {
            HStack(spacing: WH.Spacing.md) {
                ZStack {
                    Circle().fill(WH.Color.strainBlue.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: ActivityType.crossfit.symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(WH.Color.strainBlue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("CrossFit")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                    Text(crossFitSubtitle(weekCount: weekCount, last: last))
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.6))
            }
            .padding(WH.Spacing.md)
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            .padding(.horizontal, WH.Spacing.md)
        }
        .buttonStyle(.plain)
    }

    private func crossFitSubtitle(weekCount: Int, last: Workout?) -> String {
        if let last {
            let when = relativeDay(last.startTs)
            let base = weekCount > 0 ? "\(weekCount) esta semana" : "Sin sesiones esta semana"
            return "\(base) · última \(when)"
        }
        return "Clasifica un entreno como CrossFit para empezar"
    }

    // MARK: - Workouts list

    private func assessment(for workout: Workout) -> BoutAssessment {
        ActivityBoutClassifier.assess(
            workout,
            among: workouts,
            isConfirmed: labelStore.isConfirmed(workout),
            isDismissed: labelStore.isDismissed(workout.id)
        )
    }

    /// Actividades del día seleccionado, de más reciente a más antigua.
    private var selectedDayActivities: [Workout] {
        workouts.filter { isOnSelectedDay($0.startTs) }
            .sorted { $0.startTs > $1.startTs }
    }

    private var activityGroups: [DayActivitySections.Grouped] {
        DayActivitySections.group(
            workouts: selectedDayActivities,
            assess: assessment(for:),
            isConfirmed: { labelStore.isConfirmed($0) },
            isDismissed: { labelStore.isDismissed($0.id) },
            hasActivityOnlyLabel: { labelStore.activityOnlyType(for: $0) != nil }
        )
    }

    private func isOnSelectedDay(_ ts: Int) -> Bool {
        Calendar.current.isDate(
            Date(timeIntervalSince1970: TimeInterval(ts)),
            inSameDayAs: selectedDate
        )
    }

    private func isTrainingBout(_ w: Workout) -> Bool {
        !labelStore.isDismissed(w.id)
            && (labelStore.isConfirmed(w) || assessment(for: w).category == .likelyWorkout)
    }

    private var dayActivitiesSubtitle: String {
        let groups = activityGroups
        if groups.isEmpty { return "Sin actividad detectada" }
        return groups.map { group in
            let n = group.items.count
            let label: String = {
                switch group.section {
                case .workouts:    return n == 1 ? "entreno" : "entrenos"
                case .life:        return n == 1 ? "actividad" : "actividades"
                case .dailyRhythm: return n == 1 ? "ritmo" : "ritmos"
                case .hrSignals:   return n == 1 ? "señal FC" : "señales FC"
                }
            }()
            return "\(n) \(label)"
        }.joined(separator: " · ")
    }

    private var activityListTitle: String {
        if isViewingToday { return "HOY" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return fmt.string(from: selectedDate).capitalized
    }

    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.lg) {
            dayWorkoutCard
            summaryStrip
            if activityGroups.isEmpty {
                VStack(alignment: .leading, spacing: WH.Spacing.sm) {
                    Text(activityListTitle)
                        .font(WH.Font.cardTitle)
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(1.2)
                        .padding(.horizontal, WH.Spacing.md)
                    emptyState
                }
            } else {
                VStack(alignment: .leading, spacing: WH.Spacing.xs) {
                    Text(activityListTitle)
                        .font(WH.Font.cardTitle)
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(1.2)
                    Text(dayActivitiesSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(WH.Color.textSecondary.opacity(0.75))
                }
                .padding(.horizontal, WH.Spacing.md)

                ForEach(activityGroups, id: \.section) { group in
                    activityGroupSection(group)
                }
                autoDetectNote
            }
        }
    }

    private func activityGroupSection(_ group: DayActivitySections.Grouped) -> some View {
        let collapsed = collapsedSections.contains(group.section)
        return VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Button {
                guard group.section.collapsedByDefault else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if collapsed {
                        collapsedSections.remove(group.section)
                    } else {
                        collapsedSections.insert(group.section)
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: WH.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.section.title)
                            .font(WH.Font.cardTitle)
                            .foregroundStyle(sectionAccent(group.section))
                            .tracking(1.2)
                        Text(group.section.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(WH.Color.textSecondary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: WH.Spacing.xs)
                    Text("\(group.items.count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(sectionAccent(group.section))
                        .monospacedDigit()
                    if group.section.collapsedByDefault {
                        Text(collapsed ? "Ver" : "Ocultar")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WH.Color.strainBlue)
                        Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }
                .padding(.horizontal, WH.Spacing.md)
            }
            .buttonStyle(.plain)
            .disabled(!group.section.collapsedByDefault)

            if !collapsed || !group.section.collapsedByDefault {
                boutSection(title: "", subtitle: "", items: group.items)
            }
        }
    }

    private func sectionAccent(_ section: DayActivitySection) -> Color {
        switch section {
        case .workouts:     return WH.Color.strainBlue
        case .life:         return WH.Color.textSecondary
        case .dailyRhythm:  return WH.Color.stressHigh
        case .hrSignals:    return WH.Color.recoveryYellow
        }
    }

    private func boutSection(title: String, subtitle: String, items: [Workout]) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            if !title.isEmpty || !subtitle.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if !title.isEmpty {
                        Text(title)
                            .font(WH.Font.cardTitle)
                            .foregroundStyle(WH.Color.textSecondary)
                            .tracking(1.2)
                    }
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(WH.Color.textSecondary.opacity(0.75))
                    }
                }
                .padding(.horizontal, WH.Spacing.md)
            }

            VStack(spacing: 1) {
                ForEach(items) { workout in
                    NavigationLink(
                        destination: WorkoutDetailView(
                            workout: workout,
                            labelStore: labelStore,
                            allWorkouts: workouts,
                            dayPlanStore: dayPlanStore,
                            dayKey: selectedDayKey,
                            prvnDay: programStore.program(for: selectedDate)
                        )
                    ) {
                        workoutRow(workout)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            pickerWorkout = workout
                        } label: {
                            Label("Clasificar", systemImage: "tag.fill")
                        }
                        .tint(WH.Color.strainBlue)
                    }
                }
            }
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            .padding(.horizontal, WH.Spacing.md)
        }
    }

    private var summaryStrip: some View {
        let serverCount = serverExerciseCount(for: selectedDayKey) ?? 0
        let total = max(selectedDayActivities.count, serverCount)
        let train = activityGroups.first(where: { $0.section == .workouts })?.items.count ?? 0
        let other = max(0, total - train)
        let dayMin = selectedDayActivities.reduce(0) { $0 + $1.durationS } / 60
        return HStack(spacing: WH.Spacing.lg) {
            summaryItem(value: "\(total)", unit: "total", label: "ACTIVIDADES")
            summaryItem(value: "\(train)", unit: train == 1 ? "entreno" : "entrenos", label: "ENTRENOS")
            summaryItem(value: "\(other)", unit: "otras", label: "FC / OTROS")
            summaryItem(value: dayMin > 0 ? "\(dayMin)" : "—", unit: dayMin > 0 ? "min" : nil, label: "TIEMPO")
            Spacer()
        }
        .padding(.horizontal, WH.Spacing.md)
    }

    private func summaryItem(value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(WH.Font.metricMedium(size: 26))
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(0.8)
        }
    }

    private var autoDetectNote: some View {
        HStack(spacing: WH.Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(WH.Color.textSecondary.opacity(0.6))
            Text("Detectadas por tu frecuencia cardíaca — entrenos, picos matutinos y otras subidas de FC.")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, WH.Spacing.md)
    }

    private func workoutRow(_ w: Workout) -> some View {
        let type = labelStore.effectiveType(for: w)
        let activityType = labelStore.activityOnlyType(for: w)
        let cat = assessment(for: w).category
        let isActivityOnly = labelStore.isDismissed(w.id)
        return HStack(spacing: WH.Spacing.sm) {
            Image(systemName: type?.symbol ?? activityType?.symbol ?? listIcon(for: w, category: cat))
                .font(.system(size: 15))
                .foregroundStyle(rowIconColor(type: type, activityType: activityType, category: cat, isActivityOnly: isActivityOnly, w: w))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: WH.Spacing.xs) {
                    Text(rowTitle(w, type: type, activityType: activityType, category: cat, isActivityOnly: isActivityOnly))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                    if isOnSelectedDay(w.startTs) {
                        dayKindBadge(training: isTrainingBout(w))
                    }
                }
                Text(rowSubtitle(w, type: type, activityType: activityType, category: cat))
                    .font(.system(size: 12))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            .frame(minWidth: 120, alignment: .leading)

            Text(formatDuration(w.durationS))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(WH.Color.textSecondary)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.0f", w.avgHr))
                    .font(.system(size: 14, weight: .semibold))
                    .fontWidth(.condensed)
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                Text("lpm")
                    .font(.system(size: 10))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            .frame(width: 40, alignment: .trailing)

            strainBadge(w.strain)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, WH.Spacing.md)
        .padding(.vertical, WH.Spacing.sm)
    }

    private func dayKindBadge(training: Bool) -> some View {
        Text(training ? "Entreno" : "FC")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(training ? WH.Color.strainBlue : WH.Color.recoveryYellow)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(
                (training ? WH.Color.strainBlue : WH.Color.recoveryYellow).opacity(0.15),
                in: Capsule()
            )
    }

    private func rowTitle(_ w: Workout, type: ActivityType?, activityType: ActivityType?,
                          category: BoutCategory, isActivityOnly: Bool) -> String {
        if let title = labelStore.displayTitle(for: w) { return title }
        if let type { return type.displayName }
        if let activityType { return activityType.displayName }
        if isHighPeakSpike(w) {
            return "Pico de FC · \(rowTime(w.startTs))"
        }
        if isActivityOnly { return "Actividad · \(rowTime(w.startTs))" }
        switch category {
        case .likelyWorkout: return rowDate(w.startTs)
        case .hrSpike:       return "Pico de FC · \(rowTime(w.startTs))"
        case .dailyRoutine:  return "Rutina · \(rowTime(w.startTs))"
        case .lifeActivity:  return "Actividad · \(rowTime(w.startTs))"
        }
    }

    private func rowSubtitle(_ w: Workout, type: ActivityType?, activityType: ActivityType?,
                             category: BoutCategory) -> String {
        let time = rowTime(w.startTs)
        let peak = w.peakHr >= 120 ? " · pico \(w.peakHr) lpm" : ""
        if type != nil || activityType != nil { return "\(time)\(peak)" }
        if labelStore.isDismissed(w.id) {
            return "\(time)\(peak) · no entreno"
        }
        return "\(time) · \(formatDuration(w.durationS))\(peak)"
    }

    private func isHighPeakSpike(_ w: Workout) -> Bool {
        w.peakHr >= 150 && (w.strain ?? 0) < 7
    }

    private func listIcon(for w: Workout, category: BoutCategory) -> String {
        if isHighPeakSpike(w) { return "waveform.path.ecg" }
        return category.icon
    }

    private func rowIconColor(type: ActivityType?, activityType: ActivityType?,
                              category: BoutCategory, isActivityOnly: Bool, w: Workout) -> Color {
        if type != nil { return WH.Color.strainBlue }
        if isHighPeakSpike(w) { return WH.Color.recoveryYellow }
        if isActivityOnly || activityType != nil { return WH.Color.textSecondary }
        return categoryColor(category)
    }

    private func categoryColor(_ cat: BoutCategory) -> Color {
        switch cat {
        case .likelyWorkout: return WH.Color.strainBlue
        case .hrSpike:       return WH.Color.recoveryYellow
        case .dailyRoutine:  return WH.Color.stressHigh
        case .lifeActivity:  return WH.Color.textSecondary
        }
    }

    private func strainBadge(_ strain: Double?) -> some View {
        Group {
            if let s = strain {
                Text(String(format: "%.1f", s))
                    .font(.system(size: 13, weight: .bold))
                    .fontWidth(.condensed)
                    .foregroundStyle(WH.Color.strainBlue)
                    .monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(WH.Color.strainBlue.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
            } else {
                Text("—")
                    .font(.system(size: 13))
                    .foregroundStyle(WH.Color.textSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
            }
        }
        .frame(width: 48, alignment: .center)
    }

    // MARK: - Empty / error

    private var emptyState: some View {
        VStack(spacing: WH.Spacing.sm) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(WH.Color.textSecondary)
            Text(isViewingToday
                 ? "Sin actividad detectada hoy todavía"
                 : "Sin actividad detectada este día")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            Text(emptyStateDetail)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WH.Spacing.xl)
            Button { showDayEditor = true } label: {
                Text("Definir entreno del día")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WH.Color.strainBlue)
                    .padding(.horizontal, WH.Spacing.md)
                    .padding(.vertical, WH.Spacing.sm)
                    .background(WH.Color.strainBlue.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, WH.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WH.Spacing.xxl)
    }

    private var emptyStateDetail: String {
        if !metrics.isServerConfigured {
            return "No hay servidor configurado (WHOOP_BASE_URL en Ajustes). Sin servidor no hay entrenos ni esfuerzo calculado."
        }
        if let err = errorMessage ?? metrics.lastError {
            return "\(err) Desliza hacia abajo para reintentar."
        }
        if weekRows.isEmpty && metrics.today == nil {
            return "No hay métricas en caché. Comprueba que el Mac/servidor esté encendido y desliza para sincronizar."
        }
        if selectedDayStrain != nil {
            let server = serverExerciseCount(for: selectedDayKey) ?? 0
            if server > 0 {
                return "Hay esfuerzo y el servidor cuenta \(server) actividad\(server == 1 ? "" : "es"). Desliza para sincronizar y ver la lista."
            }
            return "Hay esfuerzo registrado pero ningún entreno concreto. Desliza para sincronizar — la app reintentará detectar actividades de ese día."
        }
        return "Las actividades se detectan a partir de tu frecuencia cardíaca. Si acabas de entrenar, puede tardar unos minutos en sincronizar. Desliza hacia abajo para actualizar."
    }

    // MARK: - Day workout card

    private var dayWorkoutCard: some View {
        let resolved = resolvedDayWorkout
        let ctx = trainingContext
        return Button { showDayEditor = true } label: {
            VStack(alignment: .leading, spacing: WH.Spacing.sm) {
                HStack {
                    Text("TU ENTRENO")
                        .font(WH.Font.cardTitle)
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(1.2)
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WH.Color.strainBlue)
                }

                HStack(spacing: WH.Spacing.xs) {
                    Image(systemName: ctx.isRestDay ? "bed.double.fill" : "link")
                        .font(.system(size: 11))
                        .foregroundStyle(WH.Color.strainBlue.opacity(0.85))
                    Text("Movilidad · \(ctx.sourceLabel)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WH.Color.textSecondary)
                }

                if ctx.isRestDay {
                    HStack(spacing: WH.Spacing.sm) {
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(WH.Color.textSecondary)
                        Text("Descanso — sin entreno hoy")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(WH.Color.textSecondary)
                        Spacer()
                    }
                } else if let type = resolved.activityType {
                    HStack(spacing: WH.Spacing.sm) {
                        Image(systemName: resolved.crossfitStyle?.icon ?? type.symbol)
                            .font(.system(size: 20))
                            .foregroundStyle(WH.Color.strainBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dayWorkoutTitle(resolved))
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(WH.Color.textPrimary)
                            if let primary = resolved.primary {
                                Text("\(rowTime(primary.startTs)) · \(formatDuration(primary.durationS))")
                                    .font(WH.Font.caption)
                                    .foregroundStyle(WH.Color.textSecondary)
                            }
                        }
                        Spacer()
                    }
                } else if resolved.primary != nil {
                    HStack(spacing: WH.Spacing.sm) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(WH.Color.textSecondary)
                        Text("Actividad detectada — toca para clasificar")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(WH.Color.textSecondary)
                        Spacer()
                    }
                } else {
                    Text("Toca para definir qué entrenaste hoy")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(WH.Color.textSecondary)
                }

                if !resolved.blocksDone.isEmpty {
                    HStack(spacing: WH.Spacing.xs) {
                        ForEach(resolved.blocksDone, id: \.self) { kind in
                            Text(kind.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WH.Color.strainBlue)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(WH.Color.strainBlue.opacity(0.12), in: Capsule())
                        }
                    }
                }

                if let note = resolved.note {
                    Text(note)
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(WH.Spacing.md)
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            .padding(.horizontal, WH.Spacing.md)
        }
        .buttonStyle(.plain)
    }

    private func dayWorkoutTitle(_ resolved: ResolvedDayWorkout) -> String {
        guard let type = resolved.activityType else { return "Sin clasificar" }
        if type == .crossfit, let style = resolved.crossfitStyle, style != .regular {
            return "\(type.displayName) · \(style.displayName)"
        }
        return type.displayName
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: "wifi.slash")
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

    // MARK: - Data

    private var activityRecommendation: ActivityRecommendation? {
        guard isViewingToday else { return nil }
        let hour = Calendar.current.component(.hour, from: Date())
        let dayKey = MetricsRepository.localDayString(for: selectedDate)
        let checkIn = SleepCheckInStore.shared.entry(forDayKey: dayKey)
        let yesterdayKey = MetricsRepository.localDayString(
            for: Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        )
        let strainYesterday = weekRows.first(where: { $0.day == yesterdayKey })?.strain

        let completedMobility = Set(
            MobilitySessionKind.allCases.filter {
                MobilityCompletionStore.shared.isCompleted(dayKey: dayKey, sessionKind: $0)
            }
        )

        let ctx = trainingContext
        let recCtx = ActivityRecommendationContext(
            dayKey: dayKey,
            recoveryPercent: recoveryPercentForSelectedDay,
            strainToday: selectedDayStrain,
            strainYesterday: strainYesterday,
            prvnDay: ctx.effectivePrvnDay,
            morningFeeling: checkIn?.morningFeeling,
            activityCountToday: selectedDayActivities.count,
            trainingBoutCountToday: selectedDayActivities.filter(isTrainingBout).count,
            hourOfDay: hour,
            isToday: true,
            blocksDone: ctx.blocksDone,
            completedMobilitySessions: completedMobility,
            isRestDay: ctx.isRestDay
        )
        return ActivityRecommendationEngine.recommend(context: recCtx)
    }

    private var recoveryPercentForSelectedDay: Int? {
        let daily: DailyMetric?
        if isViewingToday {
            daily = metrics.today
                ?? weekRows.first { $0.day == MetricsRepository.localDayString(for: selectedDate) }
        } else {
            daily = selectedDayMetric
                ?? weekRows.first { $0.day == MetricsRepository.localDayString(for: selectedDate) }
        }
        return TodayMetricHelpers.recoveryPercent(
            sleep: isViewingToday ? metrics.lastNight : nil,
            daily: daily,
            sleepNights: sleepNights
        ).map { Int($0.percent.rounded()) }
    }

    private var selectedDayStrain: Double? {
        let key = MetricsRepository.localDayString(for: selectedDate)
        var strain = weekRows.first(where: { $0.day == key })?.strain
        if strain == nil || strain == 0 {
            if isViewingToday, metrics.today?.day == key, let t = metrics.today?.strain, t > 0 {
                strain = t
            } else if selectedDayMetric?.day == key, let s = selectedDayMetric?.strain, s > 0 {
                strain = s
            }
        }
        if strain == nil || strain == 0 {
            if let peak = selectedDayActivities.compactMap(\.strain).max(), peak > 0 {
                return peak
            }
        }
        return strain
    }

    private func reload() async {
        errorMessage = nil
        await metrics.refresh()
        sleepNights = await metrics.sleepNightCount()
        let (from, to) = dateRange(daysBack: 30)
        let fetched = await metrics.workouts(from: from, to: to)
        workouts = fetched
        await reloadWeekRows()
        await reloadStrainChartRows()
        await reloadSelectedDay()
        await reloadCoachReport()
        if metrics.isServerConfigured, fetched.isEmpty, selectedDayActivities.isEmpty {
            if metrics.today == nil && weekRows.isEmpty {
                errorMessage = "No se pudieron cargar métricas del servidor."
            } else if isViewingToday {
                errorMessage = nil
            }
        }
        if isLoading { isLoading = false }
    }

    private func reloadWeekRows() async {
        weekRows = await metrics.dailyLastDays(7, endingOn: selectedDate)
    }

    /// Ventana fija hasta hoy para el gráfico deslizable (no sigue al día seleccionado).
    private func reloadStrainChartRows() async {
        strainChartRows = await metrics.dailyLastDays(strainChartDayCount, endingOn: Date())
    }

    private func reloadSelectedDay() async {
        if isViewingToday {
            selectedDayMetric = nil
        } else {
            let day = MetricsRepository.localDayString(for: selectedDate)
            selectedDayMetric = await metrics.dailyMetric(forDay: day)
        }

        let cal = Calendar.current
        let dayKey = MetricsRepository.localDayString(for: selectedDate)
        let prevKey = MetricsRepository.localDayString(
            for: cal.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        )
        let startOfDay = cal.startOfDay(for: selectedDate)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        let fromTs = Int(startOfDay.timeIntervalSince1970)
        let toTs = Int(endOfDay.timeIntervalSince1970)

        let resting = restingHr(for: selectedDate)

        func loadDayWorkouts() async -> [Workout] {
            var list = await metrics.workouts(fromEpoch: fromTs, toEpoch: toTs)
            return await metrics.supplementHRElevations(in: list, for: selectedDate, restingHr: resting)
        }

        var dayList = await loadDayWorkouts()
        // Never wipe the selected day when the per-day fetch failed but the bulk reload had rows.
        if !dayList.isEmpty || selectedDayActivities.isEmpty {
            replaceWorkouts(forSelectedDay: dayList)
        }

        let strainBeforeBackfill = strainForSelectedDayIgnoringActivities()
        let serverCount = serverExerciseCount(for: dayKey) ?? 0
        if dayList.filter({ isOnSelectedDay($0.startTs) }).isEmpty,
           metrics.isServerConfigured,
           (strainBeforeBackfill ?? 0) > 0 || serverCount > 0 {
            _ = await metrics.backfillWorkouts(from: prevKey, to: dayKey)
            dayList = await loadDayWorkouts()
            replaceWorkouts(forSelectedDay: dayList)
        }

        let groups = activityGroups
        if groups.count == 1, groups[0].section == .hrSignals {
            collapsedSections.remove(.hrSignals)
        }
    }

    /// Strain del día sin inferirlo desde actividades (para decidir backfill).
    private func strainForSelectedDayIgnoringActivities() -> Double? {
        let key = MetricsRepository.localDayString(for: selectedDate)
        if isViewingToday, metrics.today?.day == key, let t = metrics.today?.strain, t > 0 {
            return t
        }
        if let s = selectedDayMetric?.strain, s > 0 { return s }
        return weekRows.first(where: { $0.day == key })?.strain
    }

    private func replaceWorkouts(forSelectedDay dayList: [Workout]) {
        let kept = workouts.filter { !isOnSelectedDay($0.startTs) }
        var byId = Dictionary(uniqueKeysWithValues: kept.map { ($0.id, $0) })
        for w in dayList { byId[w.id] = w }
        workouts = Array(byId.values)
    }

    private func restingHr(for day: Date) -> Int? {
        let key = MetricsRepository.localDayString(for: day)
        if isViewingToday {
            return weekRows.first { $0.day == key }?.restingHr ?? metrics.today?.restingHr
        }
        return selectedDayMetric?.restingHr ?? weekRows.first { $0.day == key }?.restingHr
    }

    private func dateRange(daysBack: Int) -> (from: String, to: String) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let from = cal.date(byAdding: .day, value: -daysBack, to: today) ?? today
        return (
            MetricsRepository.localDayString(for: from, calendar: cal),
            MetricsRepository.localDayString(for: today, calendar: cal)
        )
    }

    // MARK: - Formatting

    private func rowDate(_ ts: Int) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = "EEE d/M"
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private func rowTime(_ ts: Int) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private func relativeDay(_ ts: Int) -> String {
        let cal = Calendar.current
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        if cal.isDateInToday(d) { return "hoy" }
        if cal.isDateInYesterday(d) { return "ayer" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = "EEE d/M"
        return fmt.string(from: d)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let totalMin = seconds / 60
        let h = totalMin / 60
        let m = totalMin % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}

// MARK: - Preview

#Preview("Actividad — vacío") {
    WorkoutsView()
        .environmentObject(MetricsRepository(deviceId: "preview"))
        .environmentObject(RootTabRouter())
}
