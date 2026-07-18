import SwiftUI
import WhoopStore

// MARK: - MobilityView

struct MobilityView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var live: LiveViewModel
    @EnvironmentObject private var tabRouter: RootTabRouter
    @EnvironmentObject private var dayPlanStore: WorkoutDayPlanStore
    @ObservedObject private var prefs = MobilityPreferencesStore.shared
    @ObservedObject private var assessment = MobilityAssessmentStore.shared
    @ObservedObject private var completionStore = MobilityCompletionStore.shared
    @ObservedObject private var prvnStore = PRVNProgramStore.shared
    @StateObject private var labelStore = ActivityLabelStore()

    @State private var sessionKind: MobilitySessionKind = .daily
    @State private var showingFocusSettings = false
    @State private var showingAssessment = false
    @State private var showingDayEditor = false
    @State private var catalog: [MobilityExercise] = MobilityCatalogLoader.loadExercises()
    @State private var catalogError: String?
    @State private var sleepNights = 0
    @State private var showSessionRunner = false
    @State private var showingHistory = false
    @State private var dayWorkouts: [Workout] = []
    @State private var selectedDayMetric: DailyMetric?
    @State private var showingDevice = false

    private var selectedDate: Date { tabRouter.selectedDate }

    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var dayKey: String {
        MetricsRepository.localDayString(for: selectedDate)
    }

    private var trainingContext: DayTrainingContext {
        dayPlanStore.trainingContext(
            dayKey: dayKey,
            calendarDate: selectedDate,
            workouts: dayWorkouts,
            labelStore: labelStore,
            prvnStore: prvnStore,
            isTrainingBout: isTrainingBout
        )
    }

    private var routine: MobilityRoutine? {
        guard !catalog.isEmpty else { return nil }
        let ctx = trainingContext
        let prvnDay = ctx.effectivePrvnDay
        let builder = MobilityRoutineBuilder.Context(
            dayKey: dayKey,
            sessionKind: sessionKind,
            focusAreas: prefs.focusAreas,
            prvnDayType: prvnDay?.dayType,
            movementPatterns: ctx.movementPatterns,
            recoveryPercent: recoveryPercentToday,
            assessmentWeakAreas: assessment.weakAreas()
        )
        return MobilityRoutineBuilder.build(catalog: catalog, context: builder)
    }

    private var recoveryPercentToday: Int? {
        if let r = selectedDayMetric?.recovery { return Int(r.rounded()) }
        if isViewingToday {
            return TodayMetricHelpers.recoveryPercent(
                sleep: metrics.lastNight,
                daily: metrics.today,
                sleepNights: sleepNights
            ).map { Int($0.percent.rounded()) }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()

                if let error = catalogError ?? (catalog.isEmpty ? "Catálogo no disponible." : nil) {
                    emptyState(message: error)
                } else if let routine {
                    scrollContent(routine: routine)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingFocusSettings) {
                MobilityFocusSettingsView(prefs: prefs, onOpenAssessment: { showingAssessment = true })
            }
            .sheet(isPresented: $showingAssessment) {
                MobilityAssessmentView(store: assessment)
            }
            .sheet(isPresented: $showingHistory) {
                MobilityHistoryView(completionStore: completionStore)
            }
            .sheet(isPresented: $showingDevice) {
                NavigationStack {
                    LiveView()
                        .environmentObject(live)
                        .environmentObject(metrics)
                }
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingDayEditor) {
                DayWorkoutEditorView(
                    dayKey: dayKey,
                    selectedDate: selectedDate,
                    workouts: dayWorkouts,
                    labelStore: labelStore,
                    dayPlanStore: dayPlanStore,
                    programStore: prvnStore,
                    prvnDay: prvnStore.program(for: selectedDate),
                    isTrainingBout: isTrainingBout
                )
            }
            .onAppear {
                reloadCatalog()
                applyPendingMobilitySession()
            }
            .onChange(of: tabRouter.pendingMobilitySession) { _ in
                applyPendingMobilitySession()
            }
            .onChange(of: tabRouter.selectedDate) { _ in
                Task { await reloadDayWorkouts() }
            }
            .task {
                sleepNights = await metrics.sleepNightCount()
                await reloadDayWorkouts()
            }
            .fullScreenCover(isPresented: $showSessionRunner) {
                if let routine {
                    MobilitySessionRunnerView(
                        routine: routine,
                        sessionKind: sessionKind,
                        dayKey: dayKey,
                        onFinish: { showSessionRunner = false }
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func reloadCatalog() {
        do {
            catalog = try MobilityCatalogLoader.load().exercises
            catalogError = nil
        } catch {
            catalog = []
            catalogError = error.localizedDescription
        }
    }

    private func applyPendingMobilitySession() {
        if let kind = tabRouter.consumeMobilitySession() {
            sessionKind = kind
        }
    }

    private func scrollContent(routine: MobilityRoutine) -> some View {
        let ctx = trainingContext
        return ScrollView {
            VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                ScreenHeader("Movilidad") {
                    HStack(spacing: WH.Spacing.sm) {
                        StrapStatusButton(state: live.state) { showingDevice = true }
                        Button {
                            showingFocusSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(WH.Color.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Áreas de foco")
                    }
                }

                DayNavigator(selectedDate: $tabRouter.selectedDate, showsCalendarPicker: true)

                trainingContextCard(ctx)

                Picker("Sesión", selection: $sessionKind) {
                    ForEach(MobilitySessionKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                if assessment.shouldShowOnboarding {
                    MobilityAssessmentBanner(store: assessment) {
                        showingAssessment = true
                    }
                }

                MobilityHistoryCard(completionStore: completionStore) {
                    showingHistory = true
                }

                if let prvnDay = ctx.effectivePrvnDay, !ctx.isRestDay {
                    prvnContextCard(prvnDay: prvnDay, ctx: ctx)
                }

                routineBanner(routine)

                VStack(spacing: WH.Spacing.sm) {
                    ForEach(Array(routine.steps.enumerated()), id: \.element.id) { idx, step in
                        MobilityExerciseCard(step: step, index: idx + 1)
                    }
                }
            }
            .padding(WH.Spacing.md)
        }
    }

    private func trainingContextCard(_ ctx: DayTrainingContext) -> some View {
        Button { showingDayEditor = true } label: {
            HStack(spacing: WH.Spacing.sm) {
                Image(systemName: ctx.isRestDay ? "bed.double.fill" : "figure.strengthtraining.functional")
                    .foregroundStyle(WH.Color.strainBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Entreno de referencia")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WH.Color.textSecondary)
                    Text(ctx.sourceLabel)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                    if let note = ctx.note {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(WH.Color.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WH.Color.strainBlue)
            }
            .padding(WH.Spacing.md)
            .background(WH.Color.surface2,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func prvnContextCard(prvnDay: PRVNDayProgram, ctx: DayTrainingContext) -> some View {
        let patterns = ctx.movementPatterns
        let trainingBlocks = prvnDay.blocks.filter { $0.kind != .warmup && $0.kind != .other }

        return VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            HStack(spacing: WH.Spacing.xs) {
                Image(systemName: "calendar")
                    .foregroundStyle(WH.Color.strainBlue)
                Text("PRVN · \(prvnDay.dayType.displayName)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
            }

            if trainingBlocks.isEmpty {
                Text("Sin bloques de entreno en este programa.")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            } else {
                ForEach(trainingBlocks) { block in
                    let done = ctx.blocksDone.contains(block.kind)
                    HStack(alignment: .top, spacing: WH.Spacing.sm) {
                        Image(systemName: done ? "checkmark.circle.fill" : block.kind.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(done ? WH.Color.recoveryGreen : WH.Color.textSecondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.kind.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(WH.Color.textSecondary)
                            Text(PRVNBlockSummary.oneLine(for: block))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WH.Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !patterns.isEmpty {
                Text("Movilidad orientada a: \(PRVNMovementPatternParser.patternLabels(patterns))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WH.Color.strainBlue.opacity(0.9))
            }

            if !ctx.blocksDone.isEmpty {
                Text("Bloques hechos: \(ctx.blocksDone.map(\.displayName).joined(separator: ", "))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
        .padding(WH.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.surface2,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func routineBanner(_ routine: MobilityRoutine) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            VStack(alignment: .leading, spacing: WH.Spacing.xs) {
                HStack {
                    Image(systemName: bannerIcon(for: routine.sessionKind))
                        .foregroundStyle(WH.Color.strainBlue)
                    Text("~\(routine.estimatedMinutes) min · \(routine.steps.count) ejercicios")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                }
                if !routine.focusSummary.isEmpty {
                    Text("Foco: \(routine.focusSummary)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WH.Color.strainBlue.opacity(0.9))
                }
                Text(routine.rationale)
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }

            Button {
                showSessionRunner = true
            } label: {
                Text(completionStore.isCompleted(dayKey: dayKey, sessionKind: sessionKind)
                     ? "Repetir rutina"
                     : "Empezar rutina")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WH.Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WH.Spacing.sm)
                    .background(WH.Color.strainBlue.opacity(0.2),
                                in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)

            if completionStore.isCompleted(dayKey: dayKey, sessionKind: sessionKind),
               let done = completionStore.entry(dayKey: dayKey, sessionKind: sessionKind) {
                HStack(spacing: WH.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(WH.Color.recoveryGreen)
                    Text(isViewingToday
                         ? "Completada hoy · \(done.exerciseCount) ejercicios"
                         : "Completada · \(done.exerciseCount) ejercicios")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }
        }
        .padding(WH.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func bannerIcon(for kind: MobilitySessionKind) -> String {
        switch kind {
        case .daily:       return "sun.max.fill"
        case .preWorkout:  return "bolt.fill"
        case .postWorkout: return "figure.cooldown"
        case .preSleep:    return "moon.stars.fill"
        }
    }

    private func emptyState(message: String) -> some View {
        VStack(spacing: WH.Spacing.md) {
            Image(systemName: "figure.flexibility")
                .font(.system(size: 36))
                .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
            Text(message)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WH.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func isTrainingBout(_ w: Workout) -> Bool {
        !labelStore.isDismissed(w.id)
            && (labelStore.isConfirmed(w) || ActivityBoutClassifier.assess(
                w,
                among: dayWorkouts,
                isConfirmed: labelStore.isConfirmed(w),
                isDismissed: labelStore.isDismissed(w.id)
            ).category == .likelyWorkout)
    }

    private func reloadDayWorkouts() async {
        let key = dayKey
        dayWorkouts = await metrics.workouts(from: key, to: key)
        if isViewingToday {
            selectedDayMetric = metrics.today
        } else {
            selectedDayMetric = await metrics.dailyMetric(forDay: key)
        }
    }
}
