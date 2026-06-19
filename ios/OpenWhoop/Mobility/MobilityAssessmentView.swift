import SwiftUI

// MARK: - MobilityAssessmentView
// Mini-test local: rigidez 1–5 por zona (estilo GOWOD simplificado).

struct MobilityAssessmentView: View {
    @ObservedObject var store: MobilityAssessmentStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WH.Spacing.md) {
                    progressHeader

                    Text("Valora tu movilidad actual (1 = muy rígido, 5 = excelente). La rutina diaria priorizará zonas ≤ 2.")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)

                    ForEach(MobilityFocusArea.allCases) { area in
                        areaRow(area)
                    }
                }
                .padding(WH.Spacing.md)
            }
            .background(WH.Color.background)
            .navigationTitle("Test de movilidad")
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

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            HStack {
                Text("Progreso")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary)
                Spacer()
                Text("\(store.scores.ratedCount)/\(store.scores.totalAreas) zonas")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(WH.Color.strainBlue)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WH.Color.surface2)
                    Capsule()
                        .fill(WH.Color.strainBlue)
                        .frame(width: geo.size.width * progressFraction)
                }
            }
            .frame(height: 6)
            if store.scores.isComplete, let done = store.scores.completedAt {
                Text("Completado · \(done.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(WH.Color.recoveryGreen)
            }
        }
        .padding(WH.Spacing.sm)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
    }

    private var progressFraction: CGFloat {
        guard store.scores.totalAreas > 0 else { return 0 }
        return CGFloat(store.scores.ratedCount) / CGFloat(store.scores.totalAreas)
    }

    private func areaRow(_ area: MobilityFocusArea) -> some View {
        let current = store.scores.score(for: area) ?? 3
        return VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            Text(area.label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            HStack(spacing: WH.Spacing.sm) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        store.setScore(value, for: area)
                    } label: {
                        Text("\(value)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(current == value ? WH.Color.strainBlue : WH.Color.textSecondary)
                            .background(
                                current == value ? WH.Color.strainBlue.opacity(0.15) : WH.Color.surface,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(WH.Spacing.sm)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
    }
}
