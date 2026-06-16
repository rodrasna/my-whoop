import SwiftUI

// MARK: - DayWorkoutEditorView
// Editor del entreno de un día: bout principal, tipo, estilo CrossFit y bloques hechos.

struct DayWorkoutEditorView: View {
    let dayKey: String
    let selectedDate: Date
    let workouts: [Workout]
    @ObservedObject var labelStore: ActivityLabelStore
    @ObservedObject var dayPlanStore: WorkoutDayPlanStore
    let prvnDay: PRVNDayProgram?
    let isTrainingBout: (Workout) -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var primaryId: String?
    @State private var activityType: ActivityType?
    @State private var crossfitStyle: CrossFitSessionStyle?
    @State private var blocksDone: Set<ProgramBlockKind> = []
    @State private var note: String = ""

    private var sortedWorkouts: [Workout] {
        workouts.sorted { $0.startTs > $1.startTs }
    }

    private var availableBlockKinds: [ProgramBlockKind] {
        if let prvn = prvnDay {
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
            Text("Marca qué bloques hiciste realmente (p. ej. solo WOD en un clasificatorio).")
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
            TextField("Ej. Open 26.2, scaled, sin accesorios…", text: $note, axis: .vertical)
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

        if let saved, !saved.blocksDone.isEmpty {
            blocksDone = Set(saved.blocksDone)
        } else if let prvn = prvnDay {
            blocksDone = Set(prvn.blocks.map(\.kind).filter { $0 != .other })
        }

        note = saved?.note ?? ""
    }

    private func save() {
        var plan = WorkoutDayPlan(
            primaryWorkoutId: primaryId,
            activityType: activityType,
            crossfitStyle: activityType == .crossfit ? crossfitStyle : nil,
            blocksDone: Array(blocksDone).sorted(by: blockSort),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        if !plan.hasContent { plan = WorkoutDayPlan() }
        dayPlanStore.set(plan.hasContent ? plan : nil, for: dayKey)

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
