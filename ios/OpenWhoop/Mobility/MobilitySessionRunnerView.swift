import SwiftUI

// MARK: - MobilitySessionRunnerView
// Temporizador guiado ejercicio a ejercicio (estilo GOWOD).

struct MobilitySessionRunnerView: View {
    let routine: MobilityRoutine
    let sessionKind: MobilitySessionKind
    let dayKey: String
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var metrics: MetricsRepository

    @State private var index = 0
    @State private var secondsLeft: Int
    @State private var isRunning = false
    @State private var timerTask: Task<Void, Never>?

    init(
        routine: MobilityRoutine,
        sessionKind: MobilitySessionKind,
        dayKey: String,
        onFinish: @escaping () -> Void
    ) {
        self.routine = routine
        self.sessionKind = sessionKind
        self.dayKey = dayKey
        self.onFinish = onFinish
        let first = routine.steps.first?.guidedDurationSec ?? 60
        _secondsLeft = State(initialValue: first)
    }

    private var step: MobilityRoutineStep? {
        guard routine.steps.indices.contains(index) else { return nil }
        return routine.steps[index]
    }

    private var exercise: MobilityExercise? { step?.exercise }

    private var totalDuration: Int {
        step?.guidedDurationSec ?? 60
    }

    private var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1 - Double(secondsLeft) / Double(totalDuration)
    }

    var body: some View {
        ZStack {
            WH.Color.background.ignoresSafeArea()

            if let exercise {
                VStack(spacing: WH.Spacing.lg) {
                    header
                    Spacer(minLength: WH.Spacing.sm)

                    MobilityExerciseImageView(exercise: exercise, size: 160)

                    if let side = step?.side {
                        Text(side.label)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(WH.Color.strainBlue)
                    }

                    Text(step?.displayTitle ?? exercise.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, WH.Spacing.md)

                    Text(exercise.description)
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, WH.Spacing.lg)

                    if let url = URL(string: exercise.youtubeURL) {
                        Link(destination: url) {
                            Label("Ver en YouTube", systemImage: "play.rectangle.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(WH.Color.strainBlue)
                        .padding(.top, WH.Spacing.xs)
                    }

                    timerRing

                    controls

                    Spacer(minLength: WH.Spacing.sm)
                }
                .padding(WH.Spacing.md)
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { stopTimer() }
    }

    private var header: some View {
        HStack {
            Button("Cerrar") {
                stopTimer()
                dismiss()
                onFinish()
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(WH.Color.textSecondary)

            Spacer()

            Text("\(index + 1) / \(routine.steps.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textSecondary)
                .monospacedDigit()
        }
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(WH.Color.surface, lineWidth: 10)
                .frame(width: 140, height: 140)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(WH.Color.strainBlue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 140, height: 140)
                .animation(.linear(duration: 0.25), value: progress)
            Text(timeLabel)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, WH.Spacing.md)
    }

    private var timeLabel: String {
        let m = secondsLeft / 60
        let s = secondsLeft % 60
        return m > 0 ? String(format: "%d:%02d", m, s) : "\(s)"
    }

    private var controls: some View {
        HStack(spacing: WH.Spacing.xl) {
            Button {
                goPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 22))
            }
            .disabled(index == 0)
            .opacity(index == 0 ? 0.35 : 1)

            Button {
                toggleTimer()
            } label: {
                Image(systemName: isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(WH.Color.strainBlue)
            }

            Button {
                goNext()
            } label: {
                Image(systemName: index + 1 >= routine.steps.count ? "checkmark.circle.fill" : "forward.fill")
                    .font(.system(size: 22))
            }
        }
        .foregroundStyle(WH.Color.textPrimary)
    }

    private func toggleTimer() {
        if isRunning {
            stopTimer()
        } else {
            startTimer()
        }
    }

    private func startTimer() {
        guard secondsLeft > 0 else { return }
        isRunning = true
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled, secondsLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                secondsLeft -= 1
            }
            isRunning = false
            if secondsLeft == 0 {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(nanoseconds: 400_000_000)
                goNext()
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
    }

    private func resetTimerForCurrentExercise() {
        stopTimer()
        secondsLeft = step?.guidedDurationSec ?? 60
    }

    private func goPrevious() {
        guard index > 0 else { return }
        index -= 1
        resetTimerForCurrentExercise()
    }

    private func goNext() {
        stopTimer()
        if index + 1 >= routine.steps.count {
            let entry = MobilityCompletionEntry(
                dayKey: dayKey,
                sessionKind: sessionKind,
                exerciseCount: routine.steps.count,
                completedAt: Date()
            )
            MobilityCompletionStore.shared.markCompleted(
                sessionKind: sessionKind,
                exerciseCount: routine.steps.count,
                dayKey: dayKey
            )
            Task {
                await metrics.pushMobilityCompletion(entry)
            }
            dismiss()
            onFinish()
            return
        }
        index += 1
        secondsLeft = step?.guidedDurationSec ?? 60
    }
}
