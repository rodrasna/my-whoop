import SwiftUI

// MARK: - MobilityHistoryView
// Listado detallado de sesiones completadas.

struct MobilityHistoryView: View {
    @ObservedObject var completionStore: MobilityCompletionStore
    @Environment(\.dismiss) private var dismiss

    private var grouped: [(dayKey: String, entries: [MobilityCompletionEntry])] {
        let sorted = completionStore.recentEntries(limit: 30)
        let keys = Array(Set(sorted.map(\.dayKey))).sorted(by: >)
        return keys.map { key in
            (key, sorted.filter { $0.dayKey == key })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                    summaryHeader

                    if grouped.isEmpty {
                        Text("Aún no hay rutinas completadas.")
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, WH.Spacing.xl)
                    } else {
                        ForEach(grouped, id: \.dayKey) { group in
                            daySection(dayKey: group.dayKey, entries: group.entries)
                        }
                    }
                }
                .padding(WH.Spacing.md)
            }
            .background(WH.Color.background)
            .navigationTitle("Historial")
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

    private var summaryHeader: some View {
        HStack(spacing: WH.Spacing.xl) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(completionStore.currentStreak())")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                Text("días de racha")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(completionStore.totalSessions(lastDays: 7))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                Text("sesiones esta semana")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            Spacer()
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func daySection(dayKey: String, entries: [MobilityCompletionEntry]) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text(dayLabel(dayKey))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textSecondary)

            ForEach(entries, id: \.sessionKind) { entry in
                HStack(spacing: WH.Spacing.sm) {
                    Image(systemName: icon(for: entry.sessionKind))
                        .foregroundStyle(WH.Color.strainBlue)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.sessionKind.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WH.Color.textPrimary)
                        Text("\(entry.exerciseCount) ejercicios · \(timeLabel(entry.completedAt))")
                            .font(.system(size: 11))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                    Spacer()
                }
                .padding(WH.Spacing.sm)
                .background(WH.Color.surface2,
                            in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
            }
        }
    }

    private func dayLabel(_ dayKey: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        guard let date = fmt.date(from: dayKey) else { return dayKey }
        let out = DateFormatter()
        out.locale = Locale(identifier: "es_ES")
        out.dateStyle = .medium
        if Calendar.current.isDateInToday(date) { return "Hoy" }
        if Calendar.current.isDateInYesterday(date) { return "Ayer" }
        return out.string(from: date)
    }

    private func timeLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private func icon(for kind: MobilitySessionKind) -> String {
        switch kind {
        case .daily:       return "sun.max.fill"
        case .preWorkout:  return "bolt.fill"
        case .postWorkout: return "figure.cooldown"
        case .preSleep:    return "moon.stars.fill"
        }
    }
}
