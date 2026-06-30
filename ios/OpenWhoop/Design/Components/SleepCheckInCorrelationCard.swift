import SwiftUI
import Charts

// MARK: - SleepCheckInCorrelationCard
// Contrasta sensación subjetiva vs recovery de la pulsera en los últimos días.

struct SleepCheckInCorrelationCard: View {
    @ObservedObject private var store = SleepCheckInStore.shared

    private enum ChartSeries: String {
        case feeling = "Sensación"
        case recovery = "Recovery"
    }

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
        if chartPoints.count >= 2 {
            VStack(alignment: .leading, spacing: WH.Spacing.sm) {
                header
                chart
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

    private var chart: some View {
        // Swift Charts merges marks that share the same Y plottable key ("Valor") into one
        // polyline — even with `series:` — which draws spurious arcs between sensación and
        // recovery on the same day. Each metric needs its own Y key name.
        Chart {
            ForEach(chartPoints) { pt in
                LineMark(
                    x: .value("Día", pt.date),
                    y: .value(ChartSeries.feeling.rawValue, pt.feeling)
                )
                .foregroundStyle(WH.Color.sleepPurple)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.linear)

                PointMark(
                    x: .value("Día", pt.date),
                    y: .value(ChartSeries.feeling.rawValue, pt.feeling)
                )
                .foregroundStyle(WH.Color.sleepPurple)
                .symbolSize(28)
            }
            ForEach(chartPoints) { pt in
                LineMark(
                    x: .value("Día", pt.date),
                    y: .value(ChartSeries.recovery.rawValue, pt.recovery)
                )
                .foregroundStyle(WH.Color.recoveryGreen)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 4]))
                .interpolationMethod(.linear)

                PointMark(
                    x: .value("Día", pt.date),
                    y: .value(ChartSeries.recovery.rawValue, pt.recovery)
                )
                .foregroundStyle(WH.Color.recoveryGreen)
                .symbolSize(22)
                .symbol {
                    Circle()
                        .strokeBorder(WH.Color.recoveryGreen, lineWidth: 2)
                        .background(Circle().fill(WH.Color.surface))
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: chartXDomain ?? Date()...Date())
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(WH.Color.separator.opacity(0.4))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(5, chartPoints.count))) { value in
                AxisGridLine().foregroundStyle(WH.Color.separator.opacity(0.2))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(shortDate(date))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 160)
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
