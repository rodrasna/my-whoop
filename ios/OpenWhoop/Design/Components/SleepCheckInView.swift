import SwiftUI

// MARK: - SleepCheckInView
// Cuestionario breve matutino: sensación + conciliación + factores (checkboxes).

struct SleepCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var metrics: MetricsRepository

    let dayKey: String
    let dayLabel: String
    let recoveryPct: Double?
    let sleepEfficiencyPct: Double?
    let existing: SleepCheckIn?

    @State private var feeling: MorningFeeling
    @State private var onset: SleepOnset
    @State private var factors: Set<SleepFactor>
    @State private var note: String
    @State private var voiceTranscript: String
    @State private var analysis: SleepCheckInAnalysis?

    init(dayKey: String,
         dayLabel: String,
         recoveryPct: Double?,
         sleepEfficiencyPct: Double?,
         existing: SleepCheckIn?) {
        self.dayKey = dayKey
        self.dayLabel = dayLabel
        self.recoveryPct = recoveryPct
        self.sleepEfficiencyPct = sleepEfficiencyPct
        self.existing = existing
        _feeling = State(initialValue: existing?.morningFeeling ?? .ok)
        _onset = State(initialValue: existing?.onset ?? .normal)
        _factors = State(initialValue: existing?.factors ?? [])
        _note = State(initialValue: existing?.note ?? "")
        _voiceTranscript = State(initialValue: existing?.voiceTranscript ?? "")
        _analysis = State(initialValue: existing?.analysis)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                    introBlock
                    if let analysis {
                        serverAnalysisBlock(analysis)
                    }
                    if !voiceTranscript.isEmpty {
                        voiceTranscriptBlock
                    }
                    feelingSection
                    onsetSection
                    factorsSection(title: "¿Qué dificultó el sueño?",
                                   items: SleepFactor.negativeFactors)
                    factorsSection(title: "¿Qué ayudó?",
                                   items: SleepFactor.positiveFactors)
                    noteSection
                    if recoveryPct != nil || sleepEfficiencyPct != nil {
                        strapSnapshot
                    }
                }
                .padding(WH.Spacing.md)
            }
            .background(WH.Color.background)
            .navigationTitle("Cómo dormiste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(WH.Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(WH.Color.recoveryGreen)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            Text(dayLabel.uppercased())
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)
            Text("Tu sensación ayuda a contrastar lo que ves en la app con cómo te sientes de verdad.")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
    }

    private var voiceTranscriptBlock: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            sectionTitle("Tu comentario de voz")
            Text(voiceTranscript)
                .font(.system(size: 14))
                .foregroundStyle(WH.Color.textSecondary)
                .italic()
        }
        .padding(WH.Spacing.sm)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
    }

    private func serverAnalysisBlock(_ analysis: SleepCheckInAnalysis) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            sectionTitle("Contraste sensación · pulsera")
            Text(analysis.conclusion)
                .font(.system(size: 14))
                .foregroundStyle(WH.Color.textPrimary)
            if let subj = analysis.subjectiveRecoveryPct, let strap = analysis.strapRecoveryPct {
                HStack(spacing: WH.Spacing.md) {
                    Text("Sensación \(Int(subj.rounded()))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WH.Color.sleepPurple)
                    Text("Recovery \(Int(strap.rounded()))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WH.Color.recoveryGreen)
                }
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface2,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private var feelingSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionTitle("¿Cómo te levantas?")
            HStack(spacing: WH.Spacing.sm) {
                ForEach(MorningFeeling.allCases) { f in
                    Button {
                        feeling = f
                    } label: {
                        VStack(spacing: 4) {
                            Text(f.shortLabel)
                                .font(.system(size: 22))
                            Text(f.label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(feeling == f ? WH.Color.textPrimary : WH.Color.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WH.Spacing.sm)
                        .background(
                            feeling == f ? WH.Color.recoveryGreen.opacity(0.15) : WH.Color.surface,
                            in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous)
                                .stroke(feeling == f ? WH.Color.recoveryGreen.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var onsetSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionTitle("¿Conciliar el sueño?")
            VStack(spacing: WH.Spacing.xs) {
                ForEach(SleepOnset.allCases) { o in
                    Button {
                        onset = o
                    } label: {
                        HStack {
                            Image(systemName: onset == o ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(onset == o ? WH.Color.sleepPurple : WH.Color.textSecondary)
                            Text(o.label)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(WH.Color.textPrimary)
                            Spacer()
                        }
                        .padding(WH.Spacing.sm)
                        .background(WH.Color.surface,
                                    in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func factorsSection(title: String, items: [SleepFactor]) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionTitle(title)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: WH.Spacing.xs) {
                ForEach(items) { factor in
                    factorChip(factor)
                }
            }
        }
    }

    private func factorChip(_ factor: SleepFactor) -> some View {
        let selected = factors.contains(factor)
        return Button {
            if selected { factors.remove(factor) } else { factors.insert(factor) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                Text(factor.label)
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected
                             ? (factor.isPositive ? WH.Color.recoveryGreen : WH.Color.recoveryYellow)
                             : WH.Color.textSecondary)
            .padding(.horizontal, WH.Spacing.sm)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? WH.Color.surface2 : WH.Color.surface,
                in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionTitle("Nota (opcional)")
            TextField("Algo más que quieras recordar…", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .font(.system(size: 14))
                .foregroundStyle(WH.Color.textPrimary)
                .padding(WH.Spacing.sm)
                .background(WH.Color.surface,
                            in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
        }
    }

    private var strapSnapshot: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            sectionTitle("Pulsera (al guardar)")
            HStack(spacing: WH.Spacing.md) {
                if let r = recoveryPct {
                    metricPill(title: "Recovery", value: "\(Int((r * 100).rounded()))%")
                }
                if let e = sleepEfficiencyPct {
                    metricPill(title: "Eficiencia sueño", value: "\(Int(e.rounded()))%")
                }
            }
            Text("Guardamos estos valores junto a tu respuesta para ver si encajan con cómo te sientes.")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WH.Color.textPrimary)
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let checkIn = SleepCheckIn(
            dayKey: dayKey,
            morningFeeling: feeling,
            onset: onset,
            factors: factors,
            note: trimmed.isEmpty ? nil : trimmed,
            savedAt: Date(),
            recoveryPct: recoveryPct,
            sleepEfficiencyPct: sleepEfficiencyPct,
            voiceTranscript: voiceTranscript.isEmpty ? nil : voiceTranscript,
            analysis: analysis
        )
        SleepCheckInStore.shared.save(checkIn)
        Task { await metrics.pushSleepCheckIn(checkIn) }
        dismiss()
    }
}
