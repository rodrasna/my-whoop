import SwiftUI
import WhoopStore

// MARK: - MobilityTodayCard
// CTA compacto en la pestaña Hoy → abre Movilidad con la sesión sugerida.

struct MobilityTodayCard: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var tabRouter: RootTabRouter
    @EnvironmentObject private var dayPlanStore: WorkoutDayPlanStore

    @StateObject private var labelStore = ActivityLabelStore()
    @ObservedObject private var prvnStore = PRVNProgramStore.shared
    @ObservedObject private var completionStore = MobilityCompletionStore.shared

    let sleepNights: Int
    let weekRows: [DailyMetric]

    @State private var todayWorkouts: [Workout] = []

    private var dayKey: String {
        MetricsRepository.localDayString(for: Date())
    }

    private var recommendation: ActivityRecommendation? {
        let hour = Calendar.current.component(.hour, from: Date())
        let checkIn = SleepCheckInStore.shared.entry(forDayKey: dayKey)
        let yesterdayKey = MetricsRepository.localDayString(
            for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        )
        let strainYesterday = weekRows.first(where: { $0.day == yesterdayKey })?.strain
        let todayActivities = todayWorkouts.filter { workout in
            Calendar.current.isDate(
                Date(timeIntervalSince1970: TimeInterval(workout.startTs)),
                inSameDayAs: Date()
            )
        }
        let completed = Set(
            MobilitySessionKind.allCases.filter {
                completionStore.isCompleted(dayKey: dayKey, sessionKind: $0)
            }
        )
        let training = dayPlanStore.trainingContext(
            dayKey: dayKey,
            calendarDate: Date(),
            workouts: todayWorkouts,
            labelStore: labelStore,
            prvnStore: prvnStore,
            isTrainingBout: isTrainingBout
        )
        let ctx = ActivityRecommendationContext(
            dayKey: dayKey,
            recoveryPercent: recoveryPercent,
            strainToday: strainToday,
            strainYesterday: strainYesterday,
            prvnDay: training.effectivePrvnDay,
            morningFeeling: checkIn?.morningFeeling,
            activityCountToday: todayActivities.count,
            trainingBoutCountToday: todayActivities.filter(isTrainingBout).count,
            hourOfDay: hour,
            isToday: true,
            blocksDone: training.blocksDone,
            completedMobilitySessions: completed,
            isRestDay: training.isRestDay
        )
        return ActivityRecommendationEngine.recommend(context: ctx)
    }

    var body: some View {
        if let rec = recommendation,
           let session = rec.suggestedMobilitySession,
           !completionStore.isCompleted(dayKey: dayKey, sessionKind: session) {
            VStack(alignment: .leading, spacing: WH.Spacing.sm) {
                Text("MOVILIDAD")
                    .font(WH.Font.cardTitle)
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.2)

                Text(rec.primaryTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)

                Text(rec.rationale)
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)

                Button {
                    tabRouter.openMobility(session)
                } label: {
                    HStack(spacing: WH.Spacing.sm) {
                        Image(systemName: "figure.flexibility")
                        Text("Abrir rutina · \(session.label)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(WH.Color.textPrimary)
                    .padding(.vertical, WH.Spacing.sm)
                    .padding(.horizontal, WH.Spacing.md)
                    .background(WH.Color.strainBlue.opacity(0.2),
                                in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(WH.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            .task { await reloadTodayWorkouts() }
        }
    }

    private var recoveryPercent: Int? {
        TodayMetricHelpers.recoveryPercent(
            sleep: metrics.lastNight,
            daily: metrics.today,
            sleepNights: sleepNights
        ).map { Int($0.percent.rounded()) }
    }

    private var strainToday: Double? {
        let key = dayKey
        if let s = metrics.today?.strain, metrics.today?.day == key, s > 0 { return s }
        if let s = weekRows.first(where: { $0.day == key })?.strain, s > 0 { return s }
        return todayWorkouts.compactMap(\.strain).max()
    }

    private func isTrainingBout(_ w: Workout) -> Bool {
        !labelStore.isDismissed(w.id)
            && (labelStore.isConfirmed(w) || assess(w).category == .likelyWorkout)
    }

    private func assess(_ w: Workout) -> BoutAssessment {
        ActivityBoutClassifier.assess(
            w,
            among: todayWorkouts,
            isConfirmed: labelStore.isConfirmed(w),
            isDismissed: labelStore.isDismissed(w.id)
        )
    }

    private func reloadTodayWorkouts() async {
        let key = dayKey
        let fetched = await metrics.workouts(from: key, to: key)
        todayWorkouts = fetched
    }
}
