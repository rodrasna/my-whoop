import SwiftUI

// MARK: - StrapTimerCard
// Tarjeta compacta en Hoy: temporizador que vibra la pulsera al acabar.

struct StrapTimerCard: View {
    @ObservedObject var timer: StrapTimerController
    @EnvironmentObject private var live: LiveViewModel

    private let presets = [1, 3, 5, 10, 15, 20]

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.md) {
            HStack {
                Text("TEMPORIZADOR")
                    .font(WH.Font.cardTitle)
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.2)
                Spacer()
                if timer.isRunning {
                    Text(StrapTimerController.formattedRemaining(timer.remainingSeconds))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WH.Color.strainBlue)
                }
            }

            if timer.isRunning {
                Text("La pulsera vibrará al terminar.")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                Button(role: .destructive) { timer.cancel() } label: {
                    Label("Cancelar", systemImage: "xmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WH.Spacing.sm)
                }
                .buttonStyle(.plain)
                .foregroundStyle(WH.Color.recoveryRed)
                .padding(WH.Spacing.sm)
                .background(WH.Color.surface2,
                            in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: WH.Spacing.xs) {
                        ForEach(presets, id: \.self) { min in
                            Button {
                                timer.selectedMinutes = min
                            } label: {
                                Text("\(min) min")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        timer.selectedMinutes == min
                                            ? WH.Color.strainBlue.opacity(0.25)
                                            : WH.Color.surface2,
                                        in: Capsule()
                                    )
                                    .foregroundStyle(
                                        timer.selectedMinutes == min
                                            ? WH.Color.strainBlue
                                            : WH.Color.textSecondary
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    guard live.state.connected else { return }
                    timer.start()
                } label: {
                    HStack(spacing: WH.Spacing.xs) {
                        Image(systemName: "timer")
                        Text(live.state.connected ? "Iniciar \(timer.selectedMinutes) min" : "Conecta la pulsera")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(live.state.connected ? WH.Color.textPrimary : WH.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WH.Spacing.sm)
                    .background(WH.Color.surface2,
                                in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!live.state.connected)
            }
        }
        .padding(WH.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        .onAppear { timer.attach(live: live) }
    }
}
