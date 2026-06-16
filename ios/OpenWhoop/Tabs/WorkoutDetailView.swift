import SwiftUI

// MARK: - WorkoutDetailView
// Push destination for a single detected workout bout.
// Header → stats strip → HR-zone breakdown.

struct WorkoutDetailView: View {
    let workout: Workout
    @ObservedObject var labelStore: ActivityLabelStore
    var allWorkouts: [Workout] = []
    var dayPlanStore: WorkoutDayPlanStore? = nil
    var dayKey: String? = nil
    var prvnDay: PRVNDayProgram? = nil

    @EnvironmentObject private var metrics: MetricsRepository
    @State private var showPicker = false
    @State private var showDayEditor = false

    private var effectiveType: ActivityType? { labelStore.effectiveType(for: workout) }
    private var activityOnlyType: ActivityType? { labelStore.activityOnlyType(for: workout) }
    private var isManual: Bool { labelStore.manualLabel(for: workout.id) != nil }
    private var assessment: BoutAssessment {
        ActivityBoutClassifier.assess(
            workout,
            among: allWorkouts.isEmpty ? [workout] : allWorkouts,
            isConfirmed: labelStore.isConfirmed(workout),
            isDismissed: labelStore.isDismissed(workout.id)
        )
    }
    /// Sugerencia automática (k-NN sobre tu histórico) solo si aún no hay clasificación.
    private var suggestion: ActivityType? {
        effectiveType == nil ? labelStore.suggestion(for: workout) : nil
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            WH.Color.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                    assessmentBanner
                    headerSection
                    WorkoutHRChartView(workout: workout)
                    activitySection
                    structureSection
                    statsStrip
                    zoneSection
                    contextSection
                    Spacer(minLength: WH.Spacing.xl)
                }
                .padding(WH.Spacing.md)
            }
            .background(WH.Color.background)
        }
        .navigationTitle(labelStore.isDismissed(workout.id) || assessment.category != .likelyWorkout
                         ? "Actividad" : "Entreno")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPicker) {
            ActivityPickerView(workout: workout, labelStore: labelStore)
        }
        .sheet(isPresented: $showDayEditor) {
            if let dayPlanStore, let dayKey {
                DayWorkoutEditorView(
                    dayKey: dayKey,
                    selectedDate: Date(timeIntervalSince1970: TimeInterval(workout.startTs)),
                    workouts: dayWorkouts,
                    labelStore: labelStore,
                    dayPlanStore: dayPlanStore,
                    prvnDay: prvnDay,
                    isTrainingBout: { w in
                        !labelStore.isDismissed(w.id)
                            && (labelStore.isConfirmed(w) || ActivityBoutClassifier.assess(
                                w,
                                among: allWorkouts.isEmpty ? [workout] : allWorkouts,
                                isConfirmed: labelStore.isConfirmed(w),
                                isDismissed: labelStore.isDismissed(w.id)
                            ).category == .likelyWorkout)
                    }
                )
            }
        }
    }

    private var dayWorkouts: [Workout] {
        let cal = Calendar.current
        let day = Date(timeIntervalSince1970: TimeInterval(workout.startTs))
        return (allWorkouts.isEmpty ? [workout] : allWorkouts).filter {
            cal.isDate(Date(timeIntervalSince1970: TimeInterval($0.startTs)), inSameDayAs: day)
        }
    }

    // MARK: - Assessment banner

    private var assessmentBanner: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            HStack(spacing: WH.Spacing.sm) {
                Image(systemName: assessment.category.icon)
                    .foregroundStyle(bannerAccent)
                Text(assessment.category.listTitle.uppercased())
                    .font(WH.Font.cardTitle)
                    .foregroundStyle(bannerAccent)
                    .tracking(1.0)
                Spacer()
            }
            Text(assessment.reason)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if labelStore.isDismissed(workout.id) {
                Button {
                    labelStore.restoreAsWorkoutCandidate(workout.id)
                } label: {
                    Text("Volver a considerar como entreno")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WH.Spacing.sm)
                        .background(WH.Color.strainBlue.opacity(0.2), in: Capsule())
                        .foregroundStyle(WH.Color.strainBlue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(WH.Spacing.md)
        .background(bannerAccent.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private var bannerAccent: Color {
        switch assessment.category {
        case .likelyWorkout:  return WH.Color.strainBlue
        case .hrSpike:        return WH.Color.recoveryYellow
        case .dailyRoutine:   return WH.Color.stressHigh
        case .lifeActivity:   return WH.Color.textSecondary
        }
    }

    // MARK: - Activity type (etiquetado)

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("CLASIFICACIÓN")
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)

            Button { showPicker = true } label: {
                HStack(spacing: WH.Spacing.md) {
                    Image(systemName: effectiveType?.symbol ?? activityOnlyType?.symbol ?? suggestion?.symbol ?? "questionmark.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(effectiveType != nil ? WH.Color.strainBlue
                                         : (activityOnlyType != nil ? WH.Color.textSecondary
                                            : (suggestion != nil ? WH.Color.strainBlue.opacity(0.7) : WH.Color.textSecondary)))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(labelStore.displayTitle(for: workout)
                             ?? effectiveType?.displayName
                             ?? activityOnlyType?.displayName
                             ?? suggestion.map { "¿\($0.displayName)?" }
                             ?? (labelStore.isDismissed(workout.id) ? "Actividad" : "Sin clasificar"))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(WH.Color.textPrimary)
                        Text(titleSubtitle)
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WH.Color.textSecondary.opacity(0.6))
                }
                .padding(WH.Spacing.md)
                .background(WH.Color.surface,
                            in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var titleSubtitle: String {
        if effectiveType != nil {
            return isManual ? "Clasificado por ti" : "Sugerido · toca para cambiar"
        }
        if activityOnlyType != nil {
            return "Actividad cotidiana · no cuenta como entreno"
        }
        if labelStore.isDismissed(workout.id) {
            return "Marcado como actividad · toca para etiquetar o revertir"
        }
        if suggestion != nil { return "Sugerido según tus sesiones · toca para confirmar" }
        return "Toca para asignar el tipo"
    }

    @ViewBuilder
    private var structureSection: some View {
        if let dayPlanStore, let dayKey {
            let resolved = dayPlanStore.resolve(
                dayKey: dayKey,
                workouts: dayWorkouts,
                labelStore: labelStore,
                prvnDay: prvnDay,
                isTrainingBout: { w in
                    !labelStore.isDismissed(w.id)
                        && (labelStore.isConfirmed(w)
                            || ActivityBoutClassifier.assess(
                                w,
                                among: allWorkouts.isEmpty ? [workout] : allWorkouts,
                                isConfirmed: labelStore.isConfirmed(w),
                                isDismissed: labelStore.isDismissed(w.id)
                            ).category == .likelyWorkout)
                }
            )
            if !resolved.blocksDone.isEmpty || resolved.note != nil || dayPlanStore.plan(for: dayKey) != nil {
                VStack(alignment: .leading, spacing: WH.Spacing.sm) {
                    HStack {
                        Text("ESTRUCTURA DEL DÍA")
                            .font(WH.Font.cardTitle)
                            .foregroundStyle(WH.Color.textSecondary)
                            .tracking(1.2)
                        Spacer()
                        Button("Editar") { showDayEditor = true }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WH.Color.strainBlue)
                    }
                    if !resolved.blocksDone.isEmpty {
                        HStack(spacing: WH.Spacing.xs) {
                            ForEach(resolved.blocksDone, id: \.self) { kind in
                                Label(kind.displayName, systemImage: kind.icon)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(WH.Color.strainBlue)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(WH.Color.strainBlue.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                    if let note = resolved.note {
                        Text(note)
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }
                .padding(WH.Spacing.md)
                .background(WH.Color.surface,
                            in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            Text(formattedDate)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            HStack(spacing: WH.Spacing.sm) {
                Text(formattedTime)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(WH.Color.textSecondary)
                Text("·")
                    .foregroundStyle(WH.Color.textSecondary)
                Text(formattedDuration)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(WH.Color.strainBlue)
                if let kind = workout.kind {
                    Text("·")
                        .foregroundStyle(WH.Color.textSecondary)
                    Text(kind)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }
        }
        .padding(WH.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    // MARK: - Stats strip

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statCell(label: "STRAIN",
                     value: workout.strain.map { String(format: "%.1f", $0) } ?? "—",
                     unit: workout.strain != nil ? "/ 21" : nil,
                     color: WH.Color.strainBlue)
            divider
            statCell(label: "FC MEDIA",
                     value: String(format: "%.0f", workout.avgHr),
                     unit: "lpm",
                     color: WH.Color.textPrimary)
            divider
            statCell(label: "FC PICO",
                     value: "\(workout.peakHr)",
                     unit: "lpm",
                     color: WH.Color.recoveryRed)
            divider
            statCell(label: "CALORÍAS",
                     value: workout.caloriesKcal.map { String(format: "%.0f", $0) } ?? "—",
                     unit: workout.caloriesKcal != nil ? "kcal" : nil,
                     color: workout.caloriesKcal != nil ? WH.Color.recoveryYellow : WH.Color.textSecondary)
        }
        .padding(.vertical, WH.Spacing.sm)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(WH.Color.separator)
            .frame(width: 1, height: 40)
    }

    private func statCell(label: String, value: String, unit: String?, color: Color) -> some View {
        VStack(spacing: WH.Spacing.xs) {
            Text(label)
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.0)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .fontWidth(.condensed)
                    .foregroundStyle(value == "—" ? WH.Color.textSecondary : color)
                    .monospacedDigit()
                if let u = unit, value != "—" {
                    Text(u)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Zone breakdown

    private var zoneSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionHeader("Zonas de FC")

            VStack(spacing: WH.Spacing.xs) {
                ForEach(0..<6, id: \.self) { zone in
                    zoneRow(zone: zone)
                }
            }
            .padding(WH.Spacing.md)
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
    }

    private func zoneRow(zone: Int) -> some View {
        let pct = workout.zoneTimePct[zone] ?? 0.0
        let mins = Double(workout.durationS) * pct / 100.0 / 60.0
        let color = zoneColor(zone)
        let label = zoneLabel(zone)

        return VStack(spacing: 4) {
            HStack {
                // Zone dot + label
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text("Z\(zone)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .frame(width: 22, alignment: .leading)
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(WH.Color.textSecondary)
                Spacer()
                // Minutes + percentage
                Text(formatZoneMins(mins))
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .fontWidth(.condensed)
                    .foregroundStyle(WH.Color.textSecondary)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                Text(String(format: "%.0f%%", pct))
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .fontWidth(.condensed)
                    .foregroundStyle(pct > 0 ? color : WH.Color.textSecondary)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
            // Horizontal bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color)
                        .frame(width: max(2, geo.size.width * CGFloat(pct / 100.0)), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Context section (HRmax + HRR)

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionHeader("Contexto")
            HStack(spacing: WH.Spacing.sm) {
                if let hrmax = workout.hrmax {
                    contextCell(
                        label: "FC MÁX",
                        value: String(format: "%.0f", hrmax),
                        unit: "bpm",
                        note: workout.hrmaxSource.isEmpty ? nil : "(\(workout.hrmaxSource))"
                    )
                }
                if let hrr = workout.avgHrrPct {
                    contextCell(
                        label: "AVG %HRR",
                        value: String(format: "%.0f", hrr),
                        unit: "%",
                        note: nil
                    )
                }
            }
        }
    }

    private func contextCell(label: String, value: String, unit: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            Text(label)
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.0)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .fontWidth(.condensed)
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            if let note {
                Text(note)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
        .padding(WH.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(WH.Font.cardTitle)
            .foregroundStyle(WH.Color.textSecondary)
            .tracking(1.5)
            .padding(.top, WH.Spacing.xs)
    }

    private var formattedDate: String {
        let d = Date(timeIntervalSince1970: TimeInterval(workout.startTs))
        let fmt = DateFormatter()
        fmt.dateStyle = .full
        fmt.timeStyle = .none
        return fmt.string(from: d)
    }

    private var formattedTime: String {
        let d = Date(timeIntervalSince1970: TimeInterval(workout.startTs))
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return fmt.string(from: d)
    }

    private var formattedDuration: String {
        let totalMin = workout.durationS / 60
        let h = totalMin / 60
        let m = totalMin % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0           { return "\(h)h" }
        return "\(m)m"
    }

    private func formatZoneMins(_ mins: Double) -> String {
        if mins < 1.0 { return "<1m" }
        return "\(Int(mins.rounded()))m"
    }

    private func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 0: return WH.Color.textSecondary
        case 1: return WH.Color.teal
        case 2: return WH.Color.recoveryGreen
        case 3: return WH.Color.recoveryYellow
        case 4: return Color(hex: "#FF8C00")
        case 5: return WH.Color.recoveryRed
        default: return WH.Color.textSecondary
        }
    }

    private func zoneLabel(_ zone: Int) -> String {
        switch zone {
        case 0: return "Reposo"
        case 1: return "Muy ligera"
        case 2: return "Ligera"
        case 3: return "Moderada"
        case 4: return "Intensa"
        case 5: return "Máxima"
        default: return "Zona \(zone)"
        }
    }
}
