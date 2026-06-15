import SwiftUI

// MARK: - CrossFitView
// Pantalla dedicada a CrossFit (actividad principal del usuario). Filtra los entrenos
// clasificados como CrossFit y muestra volumen semanal + sesiones. Se llega desde la
// tarjeta hero de la pestaña Actividad.

struct CrossFitView: View {
    let workouts: [Workout]
    @ObservedObject var labelStore: ActivityLabelStore

    private var sessions: [Workout] {
        workouts.filter { labelStore.effectiveType(for: $0) == .crossfit }
            .sorted { $0.startTs > $1.startTs }
    }

    var body: some View {
        ZStack {
            WH.Color.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                    if sessions.isEmpty {
                        emptyState
                    } else {
                        summaryStrip
                        WeeklyBarChart(
                            title: "Volumen semanal (min)",
                            points: weeklyMinutes(),
                            barColor: WH.Color.strainBlue,
                            formatValue: { "\(Int($0))" }
                        )
                        sessionsSection
                    }
                    Spacer(minLength: WH.Spacing.xl)
                }
                .padding(WH.Spacing.md)
            }
            .background(WH.Color.background)
        }
        .navigationTitle("CrossFit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    // MARK: - Summary

    private var summaryStrip: some View {
        let weekCount = sessionsThisWeek()
        let totalMin = sessions.reduce(0) { $0 + $1.durationS } / 60
        let strains = sessions.compactMap(\.strain)
        let avgStrain = strains.isEmpty ? nil : strains.reduce(0, +) / Double(strains.count)
        return HStack(spacing: WH.Spacing.lg) {
            summaryItem(value: "\(weekCount)", unit: weekCount == 1 ? "sesión" : "sesiones", label: "ESTA SEMANA")
            summaryItem(value: "\(totalMin)", unit: "min", label: "TIEMPO TOTAL")
            summaryItem(value: avgStrain.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") } ?? "—",
                        unit: "/ 21", label: "STRAIN MEDIO")
            Spacer()
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func summaryItem(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(WH.Font.metricMedium(size: 24))
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(0.8)
        }
    }

    // MARK: - Sessions list

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("SESIONES")
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)
                .padding(.horizontal, WH.Spacing.xs)

            VStack(spacing: 1) {
                ForEach(sessions) { w in
                    NavigationLink(destination: WorkoutDetailView(workout: w, labelStore: labelStore)) {
                        sessionRow(w)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
    }

    private func sessionRow(_ w: Workout) -> some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: ActivityType.crossfit.symbol)
                .font(.system(size: 16))
                .foregroundStyle(WH.Color.strainBlue)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(rowDate(w.startTs))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                Text("\(rowTime(w.startTs)) · \(formatDuration(w.durationS))")
                    .font(.system(size: 12))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            Spacer()
            if let s = w.strain {
                Text(String(format: "%.1f", s).replacingOccurrences(of: ".", with: ","))
                    .font(.system(size: 14, weight: .bold))
                    .fontWidth(.condensed)
                    .foregroundStyle(WH.Color.strainBlue)
                    .monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(WH.Color.strainBlue.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, WH.Spacing.md)
        .padding(.vertical, WH.Spacing.sm)
    }

    private var emptyState: some View {
        VStack(spacing: WH.Spacing.sm) {
            Image(systemName: ActivityType.crossfit.symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(WH.Color.textSecondary)
            Text("Aún no hay sesiones de CrossFit")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            Text("Clasifica un entreno detectado como CrossFit desde su detalle y aparecerá aquí.")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WH.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WH.Spacing.xxl)
    }

    // MARK: - Computations

    private func sessionsThisWeek() -> Int {
        let cal = Calendar.current
        let weekStart = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return sessions.filter { Date(timeIntervalSince1970: TimeInterval($0.startTs)) >= weekStart }.count
    }

    /// Minutos de CrossFit por día en los últimos 7 días (local).
    private func weeklyMinutes() -> [WeeklyBarPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekdayFmt = DateFormatter()
        weekdayFmt.locale = Locale(identifier: "es_ES")
        weekdayFmt.dateFormat = "EEE"

        return (0..<7).compactMap { offset -> WeeklyBarPoint? in
            guard let day = cal.date(byAdding: .day, value: -(6 - offset), to: today) else { return nil }
            let mins = sessions
                .filter { cal.isDate(Date(timeIntervalSince1970: TimeInterval($0.startTs)), inSameDayAs: day) }
                .reduce(0) { $0 + $1.durationS } / 60
            let wd = weekdayFmt.string(from: day).lowercased().prefix(3)
            return WeeklyBarPoint(id: "\(offset)",
                                  weekday: String(wd),
                                  dayOfMonth: cal.component(.day, from: day),
                                  value: Double(mins),
                                  isToday: cal.isDate(day, inSameDayAs: today))
        }
    }

    // MARK: - Formatting

    private func rowDate(_ ts: Int) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = "EEE d/M"
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private func rowTime(_ ts: Int) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let h = m / 60
        let r = m % 60
        if h > 0 && r > 0 { return "\(h)h \(r)m" }
        if h > 0 { return "\(h)h" }
        return "\(r)m"
    }
}
