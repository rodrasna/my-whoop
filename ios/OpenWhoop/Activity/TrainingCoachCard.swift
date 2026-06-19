import SwiftUI

// MARK: - TrainingCoachCard

struct TrainingCoachCard: View {
    let report: TrainingDayCoachReport
    var isLoading = false
    var narrative: String? = nil
    /// When true, skips outer horizontal padding (e.g. inside WorkoutDetailView).
    var embedded = false

    private var lines: [String] { TrainingCoachCopy.lines(for: report) }

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            HStack {
                Text("ANÁLISIS")
                    .font(WH.Font.cardTitle)
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.2)
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.8).tint(WH.Color.textSecondary)
                }
            }

            Text(TrainingCoachCopy.headline(for: report))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)

            if lines.isEmpty {
                Text("Sin insights comparativos para este día.")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: WH.Spacing.xs) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: WH.Spacing.sm) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundStyle(WH.Color.strainBlue)
                                .padding(.top, 2)
                            Text(line)
                                .font(WH.Font.caption)
                                .foregroundStyle(WH.Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !report.blocks.isEmpty {
                HStack(spacing: WH.Spacing.xs) {
                    ForEach(report.blocks) { block in
                        Text(block.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WH.Color.strainBlue)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(WH.Color.strainBlue.opacity(0.12), in: Capsule())
                    }
                }
            }

            if let narrative, !narrative.isEmpty {
                Divider().overlay(WH.Color.separator)
                Text(narrative)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        .padding(.horizontal, embedded ? 0 : WH.Spacing.md)
    }
}
