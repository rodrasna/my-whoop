import SwiftUI

// MARK: - SleepCheckInCard
// Pregunta matutina con micrófono → transcripción → análisis servidor.

struct SleepCheckInCard: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @ObservedObject private var store = SleepCheckInStore.shared
    @StateObject private var voice = SleepVoiceRecorder()

    let dayKey: String
    let dayLabel: String
    let recoveryPct: Double?
    let sleepEfficiencyPct: Double?

    @State private var showingForm = false
    @State private var isAnalyzing = false
    @State private var analyzeError: String?

    private var entry: SleepCheckIn? { store.entry(forDayKey: dayKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            HStack(alignment: .top, spacing: WH.Spacing.sm) {
                VStack(alignment: .leading, spacing: WH.Spacing.xs) {
                    labelRow
                    questionBlock
                }
                Spacer(minLength: WH.Spacing.sm)
                micButton
            }

            if voice.isRecording || !voice.partialTranscript.isEmpty {
                transcriptBlock
            }

            if isAnalyzing {
                HStack(spacing: WH.Spacing.sm) {
                    ProgressView().tint(WH.Color.sleepPurple)
                    Text("Analizando tu sensación…")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }

            if let analyzeError {
                Text(analyzeError)
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.recoveryRed)
            }

            if let entry {
                filledSummary(entry)
            } else if !voice.isRecording && voice.partialTranscript.isEmpty && !isAnalyzing {
                manualLink
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        .sheet(isPresented: $showingForm) {
            SleepCheckInView(
                dayKey: dayKey,
                dayLabel: dayLabel,
                recoveryPct: recoveryPct,
                sleepEfficiencyPct: sleepEfficiencyPct,
                existing: entry
            )
        }
        .onDisappear {
            voice.cancelRecording()
        }
        .onChange(of: voice.phase) { phase in
            if case .failed(let message) = phase {
                analyzeError = message
            }
        }
    }

    private var labelRow: some View {
        HStack(spacing: WH.Spacing.xs) {
            Image(systemName: entry == nil ? "heart.text.clipboard" : "checkmark.seal.fill")
                .foregroundStyle(entry == nil ? WH.Color.recoveryYellow : WH.Color.recoveryGreen)
            Text("CÓMO TE SIENTES")
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)
        }
    }

    private var questionBlock: some View {
        Text("¿Cómo dormiste y por qué crees que fue así?")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(WH.Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var micButton: some View {
        Button {
            Task { await handleMicTap() }
        } label: {
            ZStack {
                Circle()
                    .fill(voice.isRecording ? WH.Color.recoveryRed.opacity(0.2) : WH.Color.sleepPurple.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(voice.isRecording ? WH.Color.recoveryRed : WH.Color.sleepPurple)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voice.isRecording ? "Detener grabación" : "Grabar comentario de voz")
        .disabled(isAnalyzing)
    }

    private var transcriptBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(voice.isRecording ? "Escuchando…" : "Transcripción")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
            Text(voice.partialTranscript.isEmpty ? "…" : voice.partialTranscript)
                .font(.system(size: 13))
                .foregroundStyle(WH.Color.textPrimary)
                .italic(voice.isRecording)
        }
        .padding(WH.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.surface2,
                    in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
    }

    private var manualLink: some View {
        Button {
            showingForm = true
        } label: {
            Text("O rellenar cuestionario manual")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WH.Color.strainBlue)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleMicTap() async {
        analyzeError = nil
        if voice.isRecording {
            voice.stopRecording()
            let text = voice.finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 8 else {
                analyzeError = "Habla un poco más para poder analizarlo."
                return
            }
            await analyzeAndSave(transcript: text)
        } else {
            await voice.toggleRecording()
        }
    }

    private func analyzeAndSave(transcript: String) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        if let result = await metrics.analyzeSleepCheckIn(
            transcript: transcript,
            dayKey: dayKey,
            recoveryPct: recoveryPct,
            sleepEfficiencyPct: sleepEfficiencyPct
        ) {
            let checkIn = SleepCheckIn(
                dayKey: dayKey,
                morningFeeling: result.morningFeeling,
                onset: result.onset,
                factors: result.factors,
                note: nil,
                savedAt: Date(),
                recoveryPct: recoveryPct,
                sleepEfficiencyPct: sleepEfficiencyPct,
                voiceTranscript: result.voiceTranscript,
                analysis: result.analysis
            )
            store.save(checkIn)
            await metrics.pushSleepCheckIn(checkIn)
        } else {
            // Sin servidor: guardar transcripción y abrir formulario manual
            analyzeError = "Sin análisis del servidor. Puedes completar el cuestionario manualmente."
            showingForm = true
        }
    }

    private func filledSummary(_ entry: SleepCheckIn) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Divider().overlay(WH.Color.separator)

            HStack(alignment: .firstTextBaseline, spacing: WH.Spacing.sm) {
                Text(entry.morningFeeling.shortLabel)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.morningFeeling.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WH.Color.textPrimary)
                    Text(entry.onset.label)
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                }
                Spacer()
                Button("Editar") { showingForm = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WH.Color.strainBlue)
            }

            if let analysis = entry.analysis {
                analysisBlock(analysis)
            } else if let transcript = entry.voiceTranscript {
                Text("«\(transcript)»")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                    .italic()
            }

            if !entry.factors.isEmpty {
                FlowFactorTags(factors: Array(entry.factors).sorted { $0.label < $1.label })
            }

            correlationLine(entry)
        }
    }

    private func analysisBlock(_ analysis: SleepCheckInAnalysis) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            if !analysis.sleepQualitySummary.isEmpty {
                Text(analysis.sleepQualitySummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            if let align = alignmentText(analysis.alignment) {
                Text(align)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(alignmentColor(analysis.alignment))
            }
            if !analysis.perceivedCauses.isEmpty {
                Text(analysis.perceivedCauses.joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            Text(analysis.conclusion)
                .font(.system(size: 13))
                .foregroundStyle(WH.Color.textPrimary)
        }
        .padding(WH.Spacing.sm)
        .background(alignmentColor(analysis.alignment).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
    }

    private func alignmentText(_ alignment: String) -> String? {
        switch alignment {
        case "strap_higher":
            return "Pulsera más optimista que tu sensación"
        case "body_higher":
            return "Te sientes mejor que marca la pulsera"
        case "aligned":
            return "Sensación alineada con la pulsera"
        default:
            return nil
        }
    }

    private func alignmentColor(_ alignment: String) -> Color {
        switch alignment {
        case "aligned": return WH.Color.recoveryGreen
        case "strap_higher": return WH.Color.recoveryYellow
        case "body_higher": return WH.Color.strainBlue
        default: return WH.Color.textSecondary
        }
    }

    private func correlationLine(_ entry: SleepCheckIn) -> some View {
        HStack(spacing: WH.Spacing.md) {
            if let subj = entry.analysis?.subjectiveRecoveryPct {
                Text("Sensación \(Int(subj.rounded()))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WH.Color.sleepPurple)
            }
            if let r = entry.recoveryPercent {
                Text("Recovery \(Int(r.rounded()))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            if let e = entry.sleepEfficiencyPct {
                Text("Eficiencia \(Int(e.rounded()))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
    }
}

// MARK: - Factor tags

private struct FlowFactorTags: View {
    let factors: [SleepFactor]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(factors) { f in
                    Text(f.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(f.isPositive ? WH.Color.recoveryGreen : WH.Color.recoveryYellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (f.isPositive ? WH.Color.recoveryGreen : WH.Color.recoveryYellow).opacity(0.12),
                            in: Capsule()
                        )
                }
            }
        }
    }
}
