import SwiftUI
import WhoopStore

// MARK: - WeeklyBarChart
// Barras 7 días al estilo WHOOP: columna gris en el día actual, valor encima de la barra.

struct WeeklyBarPoint: Identifiable {
    let id: String       // yyyy-MM-dd
    let weekday: String  // dom, lun, …
    let dayOfMonth: Int
    let value: Double
    let isToday: Bool
}

struct WeeklyBarChart: View {

    var title: String
    var points: [WeeklyBarPoint]
    var maxValue: Double? = nil
    var barColor: Color = WH.Color.strainBlue
    var formatValue: (Double) -> String = { String(format: "%.1f", $0) }
    var onTap: (() -> Void)? = nil

    private var computedMax: Double {
        let m = maxValue ?? points.map(\.value).max() ?? 1
        return m > 0 ? m : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Button(action: { onTap?() }) {
                HStack {
                    Text(title.uppercased())
                        .font(WH.Font.cardTitle)
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(1.2)
                    Spacer()
                    if onTap != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WH.Color.textSecondary.opacity(0.6))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)

            GeometryReader { geo in
                let barSlot = geo.size.width / CGFloat(max(points.count, 1))
                let chartH = geo.size.height - 22

                ZStack(alignment: .bottom) {
                    // Grid lines
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { _ in
                            Spacer()
                            Rectangle()
                                .fill(WH.Color.separator.opacity(0.35))
                                .frame(height: 0.5)
                        }
                    }
                    .frame(height: chartH)

                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(points) { pt in
                            ZStack(alignment: .bottom) {
                                if pt.isToday {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: barSlot * 0.72, height: chartH)
                                }

                                VStack(spacing: 4) {
                                    if pt.value > 0 {
                                        Text(formatValue(pt.value))
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundStyle(barColor)
                                            .monospacedDigit()
                                    } else {
                                        Text(" ")
                                            .font(.system(size: 11))
                                    }

                                    let h = chartH * CGFloat(pt.value / computedMax)
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(pt.value > 0 ? barColor : Color.clear)
                                        .frame(width: barSlot * 0.38, height: max(2, h))

                                    Text("\(pt.weekday) \(pt.dayOfMonth)")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(pt.isToday ? WH.Color.textPrimary : WH.Color.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(width: barSlot)
                            }
                        }
                    }
                }
            }
            .frame(height: 120)
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }
}

// MARK: - Helpers

enum WeeklyChartBuilder {
    /// Build 7 daily points ending today (local calendar), filling missing days with 0.
    static func last7Days(from rows: [DailyMetric],
                          value: (DailyMetric) -> Double?,
                          calendar: Calendar = .current) -> [WeeklyBarPoint] {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "yyyy-MM-dd"

        let weekdayFmt = DateFormatter()
        weekdayFmt.calendar = calendar
        weekdayFmt.locale = Locale(identifier: "es_ES")
        weekdayFmt.dateFormat = "EEE"

        let byDay = Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0) })
        let today = calendar.startOfDay(for: Date())

        return (0..<7).compactMap { offset -> WeeklyBarPoint? in
            guard let day = calendar.date(byAdding: .day, value: -(6 - offset), to: today) else { return nil }
            let key = MetricsRepository.localDayString(for: day, calendar: calendar)
            let wd = weekdayFmt.string(from: day).lowercased().prefix(3)
            let dom = calendar.component(.day, from: day)
            let v = byDay[key].flatMap { value($0) } ?? 0
            let isToday = calendar.isDate(day, inSameDayAs: today)
            return WeeklyBarPoint(id: key, weekday: String(wd), dayOfMonth: dom, value: v, isToday: isToday)
        }
    }
}
