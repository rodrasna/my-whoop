import SwiftUI

// MARK: - DayWorkoutEditorView
// Editor del entreno de un día: bout principal, tipo, estilo CrossFit y bloques hechos.

struct DayWorkoutEditorView: View {
    let dayKey: String
    let selectedDate: Date
    let workouts: [Workout]
    @ObservedObject var labelStore: ActivityLabelStore
    @ObservedObject var dayPlanStore: WorkoutDayPlanStore
    @ObservedObject var programStore: PRVNProgramStore
    let prvnDay: PRVNDayProgram?
    let isTrainingBout: (Workout) -> Bool

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var metrics: MetricsRepository

    @State private var primaryId: String?
    @State private var activityType: ActivityType?
    @State private var crossfitStyle: CrossFitSessionStyle?
    @State private var blocksDone: Set<ProgramBlockKind> = []
    @State private var note: String = ""
    @State private var prvnReferenceMode: PRVNReferenceMode = .calendar
    @State private var prvnReferenceDayKey: String?

    private var sortedWorkouts: [Workout] {
        workouts.sorted { $0.startTs > $1.startTs }
    }

    private var effectivePrvnDay: PRVNDayProgram? {
        switch prvnReferenceMode {
        case .rest:
            return nil
        case .calendar:
            return prvnDay
        case .otherWeekDay:
            if let key = prvnReferenceDayKey {
                return programStore.program(forDayKey: key) ?? prvnDay
            }
            return prvnDay
        }
    }

    private var availableBlockKinds: [ProgramBlockKind] {
        if let prvn = effectivePrvnDay {
            let kinds = prvn.blocks.map(\.kind).filter { $0 != .other }
            if !kinds.isEmpty { return kinds.sorted(by: blockSort) }
        }
        return [.warmup, .strength, .metcon, .accessory]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                        prvnReferenceSection
                        primarySection
                        typeSection
                        if activityType == .crossfit { crossfitStyleSection }
                        structureSection
                        noteSection
                    }
                    .padding(WH.Spacing.md)
                }
            }
            .navigationTitle(editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(WH.Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(WH.Color.strainBlue)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadDraft)
    }

    private var editorTitle: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return fmt.string(from: selectedDate).capitalized
    }

    // MARK: - Sections

    private var prvnReferenceSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionLabel("PROGRAMA DE REFERENCIA")
            Text("Coordina movilidad y análisis: elige qué WOD de PRVN aplica hoy, otro día de la semana, o descanso.")
                .font(.system(size: 11))
                .foregroundStyle(WH.Color.textSecondary)

            VStack(spacing: 1) {
                ForEach(PRVNReferenceMode.allCases) { mode in
                    Button {
                        prvnReferenceMode = mode
                        if mode == .calendar {
                            prvnReferenceDayKey = nil
                        } else if mode == .otherWeekDay, prvnReferenceDayKey == nil {
                            prvnReferenceDayKey = programStore.currentWeekDays.first?.id
                        }
                    } label: {
                        HStack(spacing: WH.Spacing.md) {
                            Image(systemName: prvnModeIcon(mode))
                                .font(.system(size: 16))
                                .foregroundStyle(prvnReferenceMode == mode ? WH.Color.strainBlue : WH.Color.textSecondary)
                                .frame(width: 28)
                            Text(mode.label)
                                .font(.system(size: 15))
                                .foregroundStyle(WH.Color.textPrimary)
                            Spacer()
                            if prvnReferenceMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(WH.Color.strainBlue)
                            }
                        }
                        .padding(.horizontal, WH.Spacing.md)
                        .padding(.vertical, WH.Spacing.sm + 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))

            if prvnReferenceMode == .otherWeekDay {
                let days = programStore.currentWeekDays
                if days.isEmpty {
                    Text("Importa la semana PRVN en CrossFit para elegir otro día.")
                        .font(.system(size: 12))
                        .foregroundStyle(WH.Color.textSecondary)
                        .padding(.top, WH.Spacing.xs)
                } else {
                    VStack(spacing: 1) {
                        ForEach(days) { day in
                            Button {
                                prvnReferenceDayKey = day.id
                                if blocksDone.isEmpty {
                                    blocksDone = Set(day.blocks.map(\.kind).filter { $0 != .other })
                                }
                            } label: {
                                HStack(spacing: WH.Spacing.sm) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(prvnDayTitle(day))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(WH.Color.textPrimary)
                                        Text(day.dayType.displayName)
                                            .font(.system(size: 11))
                                            .foregroundStyle(WH.Color.textSecondary)
                                    }
                                    Spacer()
                                    if prvnReferenceDayKey == day.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(WH.Color.strainBlue)
                                    }
                                }
                                .padding(.horizontal, WH.Spacing.md)
                                .padding(.vertical, WH.Spacing.sm)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(WH.Color.surface,
                                in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
                    .padding(.top, WH.Spacing.xs)
                }
            }
        }
    }

    private func prvnModeIcon(_ mode: PRVNReferenceMode) -> String {
        switch mode {
        case .calendar:     return "calendar"
        case .otherWeekDay: return "calendar.badge.clock"
        case .rest:         return "bed.double.fill"
        }
    }

    private func prvnDayTitle(_ day: PRVNDayProgram) -> String {
        guard let date = MetricsRepository.parseLocalDay(day.id) else { return day.id }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        return fmt.string(from: date).capitalized
    }

    private var primarySection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionLabel("SESIÓN DETECTADA")
            Text("Elige qué subida de FC corresponde a tu entreno de hoy.")
                .font(.system(size: 11))
                .foregroundStyle(WH.Color.textSecondary)

            if sortedWorkouts.isEmpty {
                Text("Sin actividad detectada — puedes guardar tipo y estructura igualmente.")
                    .font(.system(size: 14))
                    .foregroundStyle(WH.Color.textSecondary)
                    .padding(WH.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WH.Color.surface,
                                in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            } else {
                VStack(spacing: 1) {
                    ForEach(sortedWorkouts) { w in
                        Button {
                            primaryId = w.id
                            if activityType == nil {
                                activityType = labelStore.effectiveType(for: w)
                            }
                            if crossfitStyle == nil {
                                crossfitStyle = labelStore.sessionStyle(for: w)
                            }
                        } label: {
                            primaryRow(w, selected: primaryId == w.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(WH.Color.surface,
                            in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            }
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionLabel("TIPO DE ENTRENO")
            VStack(spacing: 1) {
                ForEach(ActivityType.allCases.filter { !ActivityType.activityOnlyCases.contains($0) }) { type in
                    Button {
                        activityType = type
                        if type != .crossfit { crossfitStyle = nil }
                    } label: {
                        typeRow(type, selected: activityType == type)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
    }

    private var crossfitStyleSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionLabel("ESTILO CROSSFIT")
            VStack(spacing: 1) {
                ForEach(CrossFitSessionStyle.allCases) { style in
                    Button {
                        crossfitStyle = style
                    } label: {
                        HStack(spacing: WH.Spacing.md) {
                            Image(systemName: style.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(style == .qualifier ? WH.Color.recoveryYellow : WH.Color.strainBlue)
                                .frame(width: 28)
                            Text(style.displayName)
                                .font(.system(size: 16))
                                .foregroundStyle(WH.Color.textPrimary)
                            Spacer()
                            if crossfitStyle == style {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(WH.Color.strainBlue)
                            }
                        }
                        .padding(.horizontal, WH.Spacing.md)
                        .padding(.vertical, WH.Spacing.sm + 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
    }

    private var structureSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionLabel("ESTRUCTURA")
            Text("Marca qué bloques hiciste (p. ej. solo WOD). Si no coincide con PRVN, descríbelo en notas.")
                .font(.system(size: 11))
                .foregroundStyle(WH.Color.textSecondary)

            VStack(spacing: 1) {
                ForEach(availableBlockKinds, id: \.self) { kind in
                    Button {
                        if blocksDone.contains(kind) { blocksDone.remove(kind) }
                        else { blocksDone.insert(kind) }
                    } label: {
                        HStack(spacing: WH.Spacing.md) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(blocksDone.contains(kind) ? WH.Color.strainBlue : WH.Color.textSecondary)
                                .frame(width: 28)
                            Text(kind.displayName)
                                .font(.system(size: 16))
                                .foregroundStyle(WH.Color.textPrimary)
                            Spacer()
                            Image(systemName: blocksDone.contains(kind) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(blocksDone.contains(kind) ? WH.Color.strainBlue : WH.Color.textSecondary.opacity(0.4))
                        }
                        .padding(.horizontal, WH.Spacing.md)
                        .padding(.vertical, WH.Spacing.sm + 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionLabel("NOTAS")
            TextField("Ej. Open 26.2 scaled, solo fuerza con sentadilla 5×5…", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .font(.system(size: 15))
                .foregroundStyle(WH.Color.textPrimary)
                .padding(WH.Spacing.md)
                .background(WH.Color.surface,
                            in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
    }

    // MARK: - Rows

    private func primaryRow(_ w: Workout, selected: Bool) -> some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? WH.Color.strainBlue : WH.Color.textSecondary.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryTime(w))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                Text("\(w.durationS / 60) min · FC \(Int(w.avgHr)) · strain \(w.strain.map { String(format: "%.1f", $0) } ?? "—")")
                    .font(.system(size: 12))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, WH.Spacing.md)
        .padding(.vertical, WH.Spacing.sm + 2)
        .contentShape(Rectangle())
    }

    private func typeRow(_ type: ActivityType, selected: Bool) -> some View {
        HStack(spacing: WH.Spacing.md) {
            Image(systemName: type.symbol)
                .font(.system(size: 18))
                .foregroundStyle(type == .crossfit ? WH.Color.strainBlue : WH.Color.textPrimary)
                .frame(width: 28)
            Text(type.displayName)
                .font(.system(size: 16, weight: type == .crossfit ? .semibold : .regular))
                .foregroundStyle(WH.Color.textPrimary)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WH.Color.strainBlue)
            }
        }
        .padding(.horizontal, WH.Spacing.md)
        .padding(.vertical, WH.Spacing.sm + 2)
        .contentShape(Rectangle())
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(WH.Font.cardTitle)
            .foregroundStyle(WH.Color.textSecondary)
            .tracking(1.2)
    }

    // MARK: - Actions

    private func loadDraft() {
        let saved = dayPlanStore.plan(for: dayKey)
        primaryId = saved?.primaryWorkoutId
            ?? sortedWorkouts.first(where: isTrainingBout)?.id
            ?? sortedWorkouts.first?.id

        if let primaryId, let w = workouts.first(where: { $0.id == primaryId }) {
            activityType = saved?.activityType ?? labelStore.effectiveType(for: w)
            crossfitStyle = saved?.crossfitStyle ?? labelStore.sessionStyle(for: w)
        } else {
            activityType = saved?.activityType
            crossfitStyle = saved?.crossfitStyle
        }

        if saved?.isRestDay == true {
            prvnReferenceMode = .rest
            prvnReferenceDayKey = nil
        } else if let ref = saved?.prvnReferenceDayKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            prvnReferenceMode = .otherWeekDay
            prvnReferenceDayKey = ref
        } else {
            prvnReferenceMode = .calendar
            prvnReferenceDayKey = nil
        }

        if let saved, !saved.blocksDone.isEmpty {
            blocksDone = Set(saved.blocksDone)
        } else if let prvn = effectivePrvnDay {
            blocksDone = Set(prvn.blocks.map(\.kind).filter { $0 != .other })
        }

        note = saved?.note ?? ""
    }

    private func save() {
        let refKey: String? = prvnReferenceMode == .otherWeekDay
            ? prvnReferenceDayKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            : nil
        var plan = WorkoutDayPlan(
            primaryWorkoutId: primaryId,
            activityType: activityType,
            crossfitStyle: activityType == .crossfit ? crossfitStyle : nil,
            blocksDone: Array(blocksDone).sorted(by: blockSort),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            prvnReferenceDayKey: refKey,
            isRestDay: prvnReferenceMode == .rest
        )
        if !plan.hasContent { plan = WorkoutDayPlan() }
        dayPlanStore.set(plan.hasContent ? plan : nil, for: dayKey)

        Task {
            await metrics.pushDayPlan(dayKey: dayKey, plan: plan.hasContent ? plan : nil)
        }

        if let primaryId, let w = workouts.first(where: { $0.id == primaryId }) {
            if let activityType {
                labelStore.set(activityType, for: w)
            }
            if activityType == .crossfit {
                labelStore.setSessionStyle(crossfitStyle ?? .regular, for: w)
            } else {
                labelStore.setSessionStyle(nil, for: w)
            }
        }

        dismiss()
    }

    private func primaryTime(_ w: Workout) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(w.startTs)))
    }

    private func blockSort(_ a: ProgramBlockKind, _ b: ProgramBlockKind) -> Bool {
        let order: [ProgramBlockKind] = [.warmup, .strength, .metcon, .accessory, .other]
        return (order.firstIndex(of: a) ?? 99) < (order.firstIndex(of: b) ?? 99)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
