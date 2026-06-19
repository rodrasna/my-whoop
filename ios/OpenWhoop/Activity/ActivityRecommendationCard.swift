import SwiftUI

// MARK: - ActivityRecommendationCard

struct ActivityRecommendationCard: View {
    @EnvironmentObject private var tabRouter: RootTabRouter
    @ObservedObject private var mobilityCompletion = MobilityCompletionStore.shared

    let recommendation: ActivityRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.md) {
            HStack(alignment: .top, spacing: WH.Spacing.sm) {
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .foregroundStyle(accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECOMENDACIÓN")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(1)
                    Text(recommendation.primaryTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                }
                Spacer()
            }

            Text(recommendation.rationale)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let min = recommendation.strainTargetMin, let max = recommendation.strainTargetMax {
                HStack(spacing: WH.Spacing.xs) {
                    Image(systemName: "target")
                        .font(.system(size: 11))
                    Text("Strain objetivo \(formatStrain(min))–\(formatStrain(max))")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(WH.Color.strainBlue.opacity(0.9))
            }

            if !recommendation.actions.isEmpty {
                VStack(spacing: WH.Spacing.sm) {
                    ForEach(recommendation.actions) { action in
                        actionRow(action)
                    }
                }
            }

            if let session = recommendation.suggestedMobilitySession {
                if mobilityCompletion.isCompleted(
                    dayKey: MetricsRepository.localDayString(for: Date()),
                    sessionKind: session
                ) {
                    HStack(spacing: WH.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(WH.Color.recoveryGreen)
                        Text("Movilidad · \(session.label) completada hoy")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(WH.Color.textSecondary)
                        Spacer()
                    }
                    .padding(.vertical, WH.Spacing.sm)
                    .padding(.horizontal, WH.Spacing.md)
                    .background(WH.Color.recoveryGreen.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
                } else {
                Button {
                    tabRouter.openMobility(session)
                } label: {
                    HStack(spacing: WH.Spacing.sm) {
                        Image(systemName: "figure.flexibility")
                        Text("Abrir Movilidad · \(session.label)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(WH.Color.strainBlue)
                    .padding(.vertical, WH.Spacing.sm)
                    .padding(.horizontal, WH.Spacing.md)
                    .background(WH.Color.strainBlue.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
                }
                .buttonStyle(.plain)
                }
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        .padding(.horizontal, WH.Spacing.md)
    }

    @ViewBuilder
    private func actionRow(_ action: ActivityRecommendationAction) -> some View {
        let content = actionRowContent(action)
        if let session = action.mobilitySession {
            Button {
                tabRouter.openMobility(session)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func actionRowContent(_ action: ActivityRecommendationAction) -> some View {
        HStack(alignment: .top, spacing: WH.Spacing.sm) {
            Image(systemName: action.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(WH.Color.strainBlue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                    if let min = action.durationMinutes {
                        Text("~\(min) min")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }
                Text(action.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(WH.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if action.mobilitySession != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.7))
            }
        }
        .padding(WH.Spacing.sm)
        .background(WH.Color.surface2,
                    in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
    }

    private var accentColor: Color {
        switch recommendation.kind {
        case .push:             return WH.Color.recoveryGreen
        case .maintain:         return WH.Color.strainBlue
        case .modify:           return WH.Color.recoveryYellow
        case .activeRecovery:   return WH.Color.recoveryYellow
        case .mobilityPreWOD, .mobilityDaily, .mobilityPostWorkout: return WH.Color.strainBlue
        case .rest:             return WH.Color.textSecondary
        case .sedentaryBreak:   return WH.Color.strainBlue
        case .windDown:         return WH.Color.textSecondary
        }
    }

    private var iconName: String {
        switch recommendation.kind {
        case .push:             return "flame.fill"
        case .maintain:         return "gauge.with.dots.needle.50percent"
        case .modify:           return "exclamationmark.triangle.fill"
        case .activeRecovery:   return "figure.walk"
        case .mobilityPreWOD, .mobilityDaily, .mobilityPostWorkout: return "figure.flexibility"
        case .rest:             return "bed.double.fill"
        case .sedentaryBreak:   return "figure.walk"
        case .windDown:         return "moon.stars.fill"
        }
    }

    private func formatStrain(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
