import SwiftUI

// MARK: - MobilityHistoryCard
// Resumen de los últimos 7 días + racha de consistencia.

struct MobilityHistoryCard: View {
    @ObservedObject var completionStore: MobilityCompletionStore
    var onShowDetail: () -> Void

    private var week: [MobilityWeekDaySummary] {
        completionStore.weekSummary()
    }

    private var streak: Int {
        completionStore.currentStreak()
    }

    private var weekTotal: Int {
        completionStore.totalSessions(lastDays: 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            HStack {
                Text("TU CONSISTENCIA")
                    .font(WH.Font.cardTitle)
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.2)
                Spacer()
                if weekTotal > 0 {
                    Button(action: onShowDetail) {
                        Text("Historial")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WH.Color.strainBlue)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: WH.Spacing.lg) {
                statBlock(value: "\(streak)", label: "Racha días")
                statBlock(value: "\(weekTotal)", label: "Sesiones 7d")
            }

            HStack(spacing: WH.Spacing.xs) {
                ForEach(week) { day in
                    dayCell(day)
                }
            }

            if weekTotal == 0 {
                Text("Completa una rutina guiada para empezar a trackear tu consistencia.")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
        .padding(WH.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WH.Color.textSecondary)
        }
    }

    private func dayCell(_ day: MobilityWeekDaySummary) -> some View {
        VStack(spacing: 4) {
            Text(day.weekdayShort.prefix(2).uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(day.isToday ? WH.Color.strainBlue : WH.Color.textSecondary)

            ZStack {
                Circle()
                    .fill(day.sessions.isEmpty ? WH.Color.surface2 : WH.Color.recoveryGreen.opacity(0.2))
                    .frame(width: 28, height: 28)
                if day.sessions.isEmpty {
                    Circle()
                        .stroke(WH.Color.textSecondary.opacity(0.25), lineWidth: 1)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WH.Color.recoveryGreen)
                }
            }
            .overlay {
                if day.isToday {
                    Circle()
                        .stroke(WH.Color.strainBlue, lineWidth: 2)
                        .frame(width: 32, height: 32)
                }
            }

            if day.sessions.count > 1 {
                Text("\(day.sessions.count)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(WH.Color.recoveryGreen)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
