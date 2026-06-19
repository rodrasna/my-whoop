import SwiftUI

// MARK: - MobilityAssessmentBanner
// Onboarding: invita al test de movilidad si aún no está completo.

struct MobilityAssessmentBanner: View {
    @ObservedObject var store: MobilityAssessmentStore
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            HStack(spacing: WH.Spacing.sm) {
                Image(systemName: "list.clipboard.fill")
                    .foregroundStyle(WH.Color.strainBlue)
                Text("Personaliza tu rutina")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                Spacer()
                Text("\(store.scores.ratedCount)/\(store.scores.totalAreas)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(WH.Color.textSecondary)
                    .monospacedDigit()
            }

            Text("Haz el test rápido (1–5 por zona). Las áreas más rígidas tendrán prioridad en la rutina diaria.")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: WH.Spacing.sm) {
                Button {
                    store.snoozeOnboarding(days: 7)
                } label: {
                    Text("Más tarde")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WH.Color.textSecondary)
                        .padding(.horizontal, WH.Spacing.md)
                        .padding(.vertical, WH.Spacing.xs)
                        .background(WH.Color.surface2,
                                    in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onStart) {
                    Text("Empezar test")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WH.Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WH.Spacing.xs)
                        .background(WH.Color.strainBlue.opacity(0.25),
                                    in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(WH.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.strainBlue.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous)
                .stroke(WH.Color.strainBlue.opacity(0.2), lineWidth: 1)
        )
    }
}
