import SwiftUI
import WhoopStore

// MARK: - WeeklyBarChart
// Barras 7 días al estilo WHOOP: columna gris en el día actual, valor encima de la barra.

struct WeeklyBarPoint: Identifiable {
    let id: String       // yyyy-MM-dd
    let weekday: String  // dom, lun, …
    let dayOfMonth: Int
    let value: Double
    /// Columna sombreada: día seleccionado en el navegador (no siempre «hoy»).
    let isHighlighted: Bool
}

struct WeeklyBarChart: View {

    var title: String
    var points: [WeeklyBarPoint]
    var maxValue: Double? = nil
    var barColor: Color = WH.Color.strainBlue
    var formatValue: (Double) -> String = { String(format: "%.1f", $0) }
    var onTap: (() -> Void)? = nil
    /// Al tocar una barra, pasa la clave `yyyy-MM-dd` del día.
    var onSelectDay: ((String) -> Void)? = nil
    /// Si true, barras en ScrollView horizontal (más de 7 días); la ventana no se mueve al seleccionar.
    var isScrollable: Bool = false
    var barWidth: CGFloat = 44

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

            if isScrollable {
                scrollableBars
            } else {
                fixedBars
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private var fixedBars: some View {
        GeometryReader { geo in
            let barSlot = geo.size.width / CGFloat(max(points.count, 1))
            barRow(barSlot: barSlot, chartH: geo.size.height - 22)
        }
        .frame(height: 120)
    }

    private var scrollableBars: some View {
        let chartH: CGFloat = 98
        let highlightId = points.first(where: \.isHighlighted)?.id ?? points.last?.id
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(points) { pt in
                        barColumn(pt, barSlot: barWidth, chartH: chartH)
                            .id(pt.id)
                    }
                }
                .padding(.horizontal, WH.Spacing.xs)
            }
            .frame(height: 120)
            .onAppear {
                guard let highlightId else { return }
                proxy.scrollTo(highlightId, anchor: .center)
            }
            .onChange(of: highlightId) { id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func barRow(barSlot: CGFloat, chartH: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
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
                    barColumn(pt, barSlot: barSlot, chartH: chartH)
                }
            }
        }
    }

    private func barColumn(_ pt: WeeklyBarPoint, barSlot: CGFloat, chartH: CGFloat) -> some View {
        Button {
            onSelectDay?(pt.id)
        } label: {
            ZStack(alignment: .bottom) {
                if pt.isHighlighted {
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
                        .fill(pt.value > 0 ? barColor : WH.Color.separator.opacity(0.25))
                        .frame(width: barSlot * 0.38, height: max(2, h))

                    Text("\(pt.weekday) \(pt.dayOfMonth)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(
                            pt.isHighlighted ? WH.Color.textPrimary : WH.Color.textSecondary
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: barSlot)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onSelectDay == nil)
    }
}

// MARK: - Helpers

enum WeeklyChartBuilder {
    /// Build N daily points ending on `anchor` (local calendar), filling missing days with 0.
    static func lastNDays(
        _ dayCount: Int,
        from rows: [DailyMetric],
        endingOn anchor: Date = Date(),
        highlightDayKey: String? = nil,
        value: (DailyMetric) -> Double?,
        calendar: Calendar = .current
    ) -> [WeeklyBarPoint] {
        let weekdayFmt = DateFormatter()
        weekdayFmt.calendar = calendar
        weekdayFmt.locale = Locale(identifier: "es_ES")
        weekdayFmt.dateFormat = "EEE"

        let byDay = Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0) })
        let end = calendar.startOfDay(for: anchor)
        let highlight = highlightDayKey ?? MetricsRepository.localDayString(for: end, calendar: calendar)
        let span = max(dayCount, 1)

        return (0..<span).compactMap { offset -> WeeklyBarPoint? in
            guard let day = calendar.date(byAdding: .day, value: -(span - 1 - offset), to: end) else { return nil }
            let key = MetricsRepository.localDayString(for: day, calendar: calendar)
            let wd = weekdayFmt.string(from: day).lowercased().prefix(3)
            let dom = calendar.component(.day, from: day)
            let v = byDay[key].flatMap { value($0) } ?? 0
            return WeeklyBarPoint(
                id: key,
                weekday: String(wd),
                dayOfMonth: dom,
                value: v,
                isHighlighted: key == highlight
            )
        }
    }

    /// Build 7 daily points ending on `anchor` (local calendar), filling missing days with 0.
    static func last7Days(
        from rows: [DailyMetric],
        endingOn anchor: Date = Date(),
        highlightDayKey: String? = nil,
        value: (DailyMetric) -> Double?,
        calendar: Calendar = .current
    ) -> [WeeklyBarPoint] {
        lastNDays(7, from: rows, endingOn: anchor, highlightDayKey: highlightDayKey, value: value, calendar: calendar)
    }
}
