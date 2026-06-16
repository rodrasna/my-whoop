import SwiftUI
import WhoopStore

// MARK: - Import sheet

struct PRVNProgramImportView: View {
    @ObservedObject var store: PRVNProgramStore
    @EnvironmentObject private var metrics: MetricsRepository
    @Environment(\.dismiss) private var dismiss

    @State private var pastedText = ""
    @State private var weekStart = PRVNProgramStore.monday(containing: Date())
    @State private var parsePreview: PRVNWeekProgram?
    @State private var errorMessage: String?
    @State private var isSyncing = false

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                        instructions

                        if metrics.isServerConfigured {
                            Button {
                                Task { await syncFromSugarWOD() }
                            } label: {
                                HStack(spacing: WH.Spacing.sm) {
                                    if isSyncing {
                                        ProgressView().tint(WH.Color.strainBlue)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text(isSyncing ? "Sincronizando…" : "Sincronizar desde SugarWOD")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, WH.Spacing.sm)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(WH.Color.strainBlue)
                            .disabled(isSyncing)
                            .padding(WH.Spacing.sm)
                            .background(WH.Color.surface,
                                        in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
                        }

                        DatePicker("Semana (lunes)", selection: $weekStart, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(WH.Color.strainBlue)
                            .onChange(of: weekStart) { _ in updatePreview() }

                        TextEditor(text: $pastedText)
                            .frame(minHeight: 220)
                            .padding(WH.Spacing.sm)
                            .background(WH.Color.surface,
                                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
                            .onChange(of: pastedText) { _ in updatePreview() }

                        if let err = errorMessage {
                            Text(err)
                                .font(WH.Font.caption)
                                .foregroundStyle(WH.Color.recoveryYellow)
                        }

                        if let preview = parsePreview, !preview.days.isEmpty {
                            previewSection(preview)
                        }
                    }
                    .padding(WH.Spacing.md)
                }
            }
            .navigationTitle("Importar PRVN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(WH.Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(parsePreview?.days.isEmpty ?? true)
                        .foregroundStyle(WH.Color.strainBlue)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            weekStart = PRVNProgramStore.monday(containing: weekStart)
            updatePreview()
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            Text("Pega la programación desde PRVN Español o sincroniza desde SugarWOD.")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
            Text("Usa CALENTAMIENTO, FUERZA, WOD y ACCESORIOS. Opcional: LUNES…DOMINGO para toda la semana.")
                .font(.system(size: 11))
                .foregroundStyle(WH.Color.textSecondary.opacity(0.85))
            if metrics.isServerConfigured {
                Text("SugarWOD omite cardio, recuperación y opciones que no entrenas.")
                    .font(.system(size: 11))
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.75))
            }
        }
    }

    private func syncFromSugarWOD() async {
        isSyncing = true
        errorMessage = nil
        let ok = await metrics.syncPRVNProgram(weekStart: weekStart)
        isSyncing = false
        if ok {
            weekStart = PRVNProgramStore.monday(containing: weekStart)
            dismiss()
        } else {
            errorMessage = metrics.lastPRVNSyncError
        }
    }

    private func previewSection(_ preview: PRVNWeekProgram) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("VISTA PREVIA · \(preview.days.count) DÍAS")
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.0)
            ForEach(preview.days) { day in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(dayLabel(day.id))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                        Text(day.dayType.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(dayTypeColor(day.dayType))
                    }
                    Text(blockSummary(day))
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                        .lineLimit(2)
                }
                .padding(WH.Spacing.sm)
                .background(WH.Color.surface,
                            in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
            }
        }
    }

    private func updatePreview() {
        errorMessage = nil
        let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parsePreview = nil
            return
        }
        let monday = PRVNProgramStore.monday(containing: weekStart)
        parsePreview = PRVNProgramParser.parse(trimmed, weekStart: monday)
        if parsePreview?.days.isEmpty ?? true {
            errorMessage = "No se detectaron bloques. Revisa CALENTAMIENTO / FUERZA / WOD / ACCESORIOS o nombres de día."
        }
    }

    private func save() {
        guard let preview = parsePreview, !preview.days.isEmpty else { return }
        store.importText(pastedText, weekStart: PRVNProgramStore.monday(containing: weekStart))
        dismiss()
    }

    private func dayLabel(_ key: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "es_ES")
        guard let d = fmt.date(from: key) else { return key }
        fmt.dateFormat = "EEE d MMM"
        return fmt.string(from: d).capitalized
    }

    private func blockSummary(_ day: PRVNDayProgram) -> String {
        day.blocks.map { $0.kind.displayName }.joined(separator: " · ")
    }

    private func dayTypeColor(_ type: PRVNDayType) -> Color {
        switch type {
        case .heavy:  return WH.Color.strainBlue
        case .engine: return WH.Color.recoveryYellow
        case .skill:  return WH.Color.teal
        case .mixed:  return WH.Color.textSecondary
        case .rest:   return WH.Color.recoveryGreen
        }
    }
}

// MARK: - Today card

struct PRVNTodayProgramCard: View {
    @ObservedObject var store: PRVNProgramStore
    var date: Date = Date()
    var recoveryPercent: Int?
    var syncError: String?
    var onImport: () -> Void

    private var program: PRVNDayProgram? { store.program(for: date) }

    private var headerTitle: String {
        Calendar.current.isDateInToday(date) ? "PRVN · HOY" : "PRVN · PROGRAMACIÓN"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.md) {
            HStack {
                Text(headerTitle)
                    .font(WH.Font.cardTitle)
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.2)
                Spacer()
                Button(action: onImport) {
                    Label("Importar", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WH.Color.strainBlue)
                }
                .buttonStyle(.plain)
            }

            if let program {
                readinessRow(program)
                ForEach(program.blocks.filter { $0.kind != .other }.sorted(by: blockSort)) { block in
                    NavigationLink {
                        PRVNBlockDetailView(block: block, date: date)
                    } label: {
                        blockRow(block)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Sin programación importada para este día.")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                Text("Los domingos se sincroniza sola desde SugarWOD; también puedes importar manualmente.")
                    .font(.system(size: 11))
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.8))
            }

            if let syncError {
                HStack(alignment: .top, spacing: WH.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(WH.Color.recoveryYellow)
                    Text(syncError)
                        .font(.system(size: 11))
                        .foregroundStyle(WH.Color.recoveryYellow)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func readinessRow(_ program: PRVNDayProgram) -> some View {
        HStack(spacing: WH.Spacing.sm) {
            Text(program.dayType.displayName.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WH.Color.strainBlue)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(WH.Color.strainBlue.opacity(0.15), in: Capsule())

            if let recovery = recoveryPercent {
                let min = program.dayType.suggestedRecoveryMin
                let ok = program.dayType == .rest || recovery >= min
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ok ? WH.Color.recoveryGreen : WH.Color.recoveryYellow)
                Text("Recup. \(recovery)%")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                if !ok && program.dayType != .rest {
                    Text("· día exigente para tu estado")
                        .font(.system(size: 11))
                        .foregroundStyle(WH.Color.recoveryYellow)
                }
            }
            Spacer()
        }
    }

    private func blockRow(_ block: ProgramBlock) -> some View {
        HStack(alignment: .top, spacing: WH.Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: WH.Spacing.xs) {
                    Image(systemName: block.kind.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(WH.Color.strainBlue)
                    Text(block.kind.displayName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(0.8)
                }
                Text(PRVNBlockSummary.oneLine(for: block))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary.opacity(0.6))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, WH.Spacing.xs)
    }

    private func blockSort(_ a: ProgramBlock, _ b: ProgramBlock) -> Bool {
        let order: [ProgramBlockKind] = [.warmup, .strength, .metcon, .accessory, .other]
        let ia = order.firstIndex(of: a.kind) ?? 99
        let ib = order.firstIndex(of: b.kind) ?? 99
        return ia < ib
    }
}
