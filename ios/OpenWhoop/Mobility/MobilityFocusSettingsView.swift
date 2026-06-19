import SwiftUI

// MARK: - MobilityFocusSettingsView

struct MobilityFocusSettingsView: View {
    @ObservedObject var prefs: MobilityPreferencesStore
    var onOpenAssessment: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WH.Spacing.md) {
                    Text("¿Qué quieres mejorar? La rutina diaria priorizará estas áreas.")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)

                    if let onOpenAssessment {
                        let rated = MobilityAssessmentStore.shared.scores.ratedCount
                        let total = MobilityAssessmentStore.shared.scores.totalAreas
                        Button(action: onOpenAssessment) {
                            HStack {
                                Image(systemName: "list.clipboard.fill")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Test de movilidad")
                                        .font(.system(size: 14, weight: .semibold))
                                    if rated < total {
                                        Text("\(rated)/\(total) zonas valoradas")
                                            .font(.system(size: 11))
                                            .foregroundStyle(WH.Color.textSecondary)
                                    } else {
                                        Text("Completo — retest cuando quieras")
                                            .font(.system(size: 11))
                                            .foregroundStyle(WH.Color.recoveryGreen)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(WH.Color.strainBlue)
                            .padding(WH.Spacing.sm)
                            .background(WH.Color.surface,
                                        in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: WH.Spacing.xs) {
                        ForEach(MobilityFocusArea.allCases) { area in
                            focusChip(area)
                        }
                    }
                }
                .padding(WH.Spacing.md)
            }
            .background(WH.Color.background)
            .navigationTitle("Áreas de foco")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(WH.Color.strainBlue)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func focusChip(_ area: MobilityFocusArea) -> some View {
        let selected = prefs.focusAreas.contains(area)
        return Button {
            prefs.toggle(area)
        } label: {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                Text(area.label)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? WH.Color.strainBlue : WH.Color.textSecondary)
            .padding(.horizontal, WH.Spacing.sm)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? WH.Color.strainBlue.opacity(0.12) : WH.Color.surface,
                in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}
