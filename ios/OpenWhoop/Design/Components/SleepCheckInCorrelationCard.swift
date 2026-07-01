import SwiftUI

// MARK: - SleepCheckInCorrelationCard
// Contrasta sensación subjetiva vs recovery de la pulsera en los últimos días.

struct SleepCheckInCorrelationCard: View {
    @ObservedObject private var store = SleepCheckInStore.shared

    private var chartPoints: [CorrelationPoint] {
        store.recentEntries(limit: 14)
            .compactMap { entry in
                guard let recovery = entry.recoveryPercent else { return nil }
                guard let date = MetricsRepository.parseLocalDay(entry.dayKey) else { return nil }
                return CorrelationPoint(
                    id: entry.dayKey,
                    date: date,
                    feeling: entry.feelingScore,
                    recovery: recovery
                )
            }
            .sorted { $0.date < $1.date }
    }

    private var chartXDomain: ClosedRange<Date>? {
        guard let first = chartPoints.first?.date,
              let last = chartPoints.last?.date else { return nil }
        let pad: TimeInterval = 12 * 3600
        return first.addingTimeInterval(-pad) ... last.addingTimeInterval(pad)
    }

    var body: some View {
        if chartPoints.count >= 2, let xDomain = chartXDomain {
            VStack(alignment: .leading, spacing: WH.Spacing.sm) {
                header
                CorrelationDualLineChart(points: chartPoints, xDomain: xDomain)
                    .frame(height: 160)
                legend
                if let insight = topInsight {
                    Text(insight)
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }
            .padding(WH.Spacing.md)
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "chart.xyaxis.line")
                .foregroundStyle(WH.Color.recoveryGreen)
            Text("SENSACIÓN VS RECOVERY")
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)
            Spacer()
            Text("\(chartPoints.count)d")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(WH.Color.textSecondary)
        }
    }

    private var legend: some View {
        HStack(spacing: WH.Spacing.md) {
            legendItem(color: WH.Color.sleepPurple, label: "Cómo te sientes", dashed: false)
            legendItem(color: WH.Color.recoveryGreen, label: "Recovery pulsera", dashed: true)
        }
    }

    private func legendItem(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 16, height: 2)
                .overlay {
                    if dashed {
                        RoundedRectangle(cornerRadius: 1)
                            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                    }
                }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WH.Color.textSecondary)
        }
    }

    private var topInsight: String? {
        let recent = store.recentEntries(limit: 14)
        guard recent.count >= 3 else { return nil }

        let bad = recent.filter { $0.morningFeeling.rawValue <= 2 }
        guard bad.count >= 2 else {
            let good = recent.filter { $0.morningFeeling.rawValue >= 4 }
            if good.count >= 2 {
                let factors = factorCounts(in: good, positiveOnly: true)
                if let top = factors.first {
                    return "Cuando te levantas bien, sueles marcar «\(top.key.label)»."
                }
            }
            return "Sigue respondiendo unos días más para ver patrones."
        }

        let factors = factorCounts(in: bad, positiveOnly: false)
        if let top = factors.first {
            return "En mañanas difíciles, «\(top.key.label)» aparece a menudo (\(top.value)×)."
        }
        return nil
    }

    private func factorCounts(in entries: [SleepCheckIn], positiveOnly: Bool) -> [(key: SleepFactor, value: Int)] {
        var counts: [SleepFactor: Int] = [:]
        for entry in entries {
            for f in entry.factors where f.isPositive == positiveOnly {
                counts[f, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }
    }
}

// MARK: - Custom dual-line chart (Swift Charts merges multi-series marks unpredictably)

private struct CorrelationDualLineChart: View {
    let points: [CorrelationPoint]
    let xDomain: ClosedRange<Date>

    private let yMin: Double = 0
    private let yMax: Double = 100
    private let leftPad: CGFloat = 26
    private let bottomPad: CGFloat = 20
    private let topPad: CGFloat = 6
    private let rightPad: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let plot = plotRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawGrid(context: &context, plot: plot)
                    drawSeries(
                        context: &context,
                        plot: plot,
                        values: points.map(\.feeling),
                        color: WH.Color.sleepPurple,
                        dashed: false
                    )
                    drawSeries(
                        context: &context,
                        plot: plot,
                        values: points.map(\.recovery),
                        color: WH.Color.recoveryGreen,
                        dashed: true
                    )
                    drawPoints(
                        context: &context,
                        plot: plot,
                        values: points.map(\.feeling),
                        color: WH.Color.sleepPurple,
                        filled: true,
                        radius: 5
                    )
                    drawPoints(
                        context: &context,
                        plot: plot,
                        values: points.map(\.recovery),
                        color: WH.Color.recoveryGreen,
                        filled: false,
                        radius: 4.5
                    )
                }
                yAxisLabels(plotHeight: plot.height)
                    .padding(.leading, 2)
                    .padding(.top, topPad)
                xAxisLabels(plot: plot, fullWidth: geo.size.width)
                    .padding(.top, plot.maxY + 2)
            }
        }
    }

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: leftPad,
            y: topPad,
            width: max(1, size.width - leftPad - rightPad),
            height: max(1, size.height - topPad - bottomPad)
        )
    }

    private func xPos(_ date: Date, plot: CGRect) -> CGFloat {
        let span = xDomain.upperBound.timeIntervalSince1970 - xDomain.lowerBound.timeIntervalSince1970
        guard span > 0 else { return plot.midX }
        let t = (date.timeIntervalSince1970 - xDomain.lowerBound.timeIntervalSince1970) / span
        return plot.minX + CGFloat(t) * plot.width
    }

    private func yPos(_ value: Double, plot: CGRect) -> CGFloat {
        let clamped = min(yMax, max(yMin, value))
        let t = (clamped - yMin) / (yMax - yMin)
        return plot.maxY - CGFloat(t) * plot.height
    }

    private func drawGrid(context: inout GraphicsContext, plot: CGRect) {
        for yVal in [0.0, 50.0, 100.0] {
            let y = yPos(yVal, plot: plot)
            var path = Path()
            path.move(to: CGPoint(x: plot.minX, y: y))
            path.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(path, with: .color(WH.Color.separator.opacity(0.4)), lineWidth: 0.5)
        }
        for date in xTickDates() {
            let x = xPos(date, plot: plot)
            var path = Path()
            path.move(to: CGPoint(x: x, y: plot.minY))
            path.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(path, with: .color(WH.Color.separator.opacity(0.2)), lineWidth: 0.5)
        }
    }

    private func drawSeries(
        context: inout GraphicsContext,
        plot: CGRect,
        values: [Double],
        color: Color,
        dashed: Bool
    ) {
        guard points.count >= 2 else { return }
        var path = Path()
        for (idx, pt) in points.enumerated() {
            let point = CGPoint(x: xPos(pt.date, plot: plot), y: yPos(values[idx], plot: plot))
            if idx == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        var style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        if dashed { style.dash = [5, 4] }
        context.stroke(path, with: .color(color), style: style)
    }

    private func drawPoints(
        context: inout GraphicsContext,
        plot: CGRect,
        values: [Double],
        color: Color,
        filled: Bool,
        radius: CGFloat
    ) {
        for (idx, pt) in points.enumerated() {
            let center = CGPoint(x: xPos(pt.date, plot: plot), y: yPos(values[idx], plot: plot))
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let circle = Path(ellipseIn: rect)
            if filled {
                context.fill(circle, with: .color(color))
            } else {
                context.fill(circle, with: .color(WH.Color.surface))
                context.stroke(circle, with: .color(color), lineWidth: 2)
            }
        }
    }

    private func yAxisLabels(plotHeight: CGFloat) -> some View {
        VStack {
            Text("100")
            Spacer()
            Text("50")
            Spacer()
            Text("0")
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(WH.Color.textSecondary)
        .frame(width: leftPad - 4, height: plotHeight, alignment: .trailing)
    }

    private func xAxisLabels(plot: CGRect, fullWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(xTickDates(), id: \.timeIntervalSince1970) { date in
                Text(shortDate(date))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(WH.Color.textSecondary)
                    .fixedSize()
                    .position(x: xPos(date, plot: plot), y: 8)
            }
        }
        .frame(width: fullWidth, height: bottomPad - 2, alignment: .topLeading)
    }

    private func xTickDates() -> [Date] {
        guard points.count >= 2 else { return points.map(\.date) }
        let tickCount = min(5, points.count)
        if tickCount == points.count { return points.map(\.date) }
        let lastIdx = points.count - 1
        return (0..<tickCount).map { i in
            let idx = Int((Double(i) / Double(tickCount - 1)) * Double(lastIdx))
            return points[idx].date
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d/M"
        return f.string(from: date)
    }
}

private struct CorrelationPoint: Identifiable {
    let id: String
    let date: Date
    let feeling: Double
    let recovery: Double
}
