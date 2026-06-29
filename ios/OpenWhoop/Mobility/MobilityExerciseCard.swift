import SwiftUI

// MARK: - MobilityExerciseCard

struct MobilityExerciseCard: View {
    let step: MobilityRoutineStep
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: WH.Spacing.md) {
            MobilityExerciseImageView(exercise: step.exercise)

            VStack(alignment: .leading, spacing: WH.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(index).")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(WH.Color.textSecondary)
                    Text(step.displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WH.Color.textPrimary)
                }

                Text(step.exercise.description)
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: WH.Spacing.sm) {
                    Text(step.guidedDurationLabel)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(WH.Color.textSecondary)

                    Text(step.exercise.mobilityMode.label)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(WH.Color.strainBlue.opacity(0.85))

                    if let url = URL(string: step.exercise.youtubeURL) {
                        Link(destination: url) {
                            Label("Ver en YouTube", systemImage: "play.rectangle.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(WH.Color.strainBlue)
                    }
                }
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }
}
