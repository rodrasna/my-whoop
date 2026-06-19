import SwiftUI
import Charts

// MARK: - WorkoutHRChartView
// FC durante el bout (con un pequeño margen antes/después para contexto).

struct WorkoutHRChartView: View {

    @EnvironmentObject private var metrics: MetricsRepository

    let workout: Workout
    /// Margen en segundos antes del inicio y después del fin del bout.
    var paddingSeconds: TimeInterval = 120

    @State private var points: [TrendPoint] = []
    @State private var isLoading = true
    @State private var selected: TrendPoint? = nil

    private var boutStart: Date {
        Date(timeIntervalSince1970: TimeInterval(workout.startTs))
    }
    private var boutEnd: Date {
        Date(timeIntervalSince1970: TimeInterval(workout.endTs))
    }

    private var chartStart: Date {
        boutStart.addingTimeInterval(-paddingSeconds)
    }
    private var chartEnd: Date {
        boutEnd.addingTimeInterval(paddingSeconds)
    }

    private var hrColor: Color { MetricKind.rawHR.color }

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("FRECUENCIA CARDÍACA")
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)

            Text(sessionRangeLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(WH.Color.textSecondary)

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView().tint(WH.Color.textSecondary)
                    Spacer()
                }
                .frame(height: 140)
            } else if points.count < 2 {
                Text("Sin datos de FC para este intervalo")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                chart
                    .frame(height: 160)
                legendRow
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        .task { await reload() }
    }

    @ViewBuilder
    private var chart: some View {
        let dom = yDomain
        Chart {
            RectangleMark(
                xStart: .value("Inicio", boutStart),
                xEnd: .value("Fin", boutEnd),
                yStart: .value("min", dom.lowerBound),
                yEnd: .value("max", dom.upperBound)
            )
            .foregroundStyle(WH.Color.strainBlue.opacity(0.12))

            ForEach(points) { pt in
                LineMark(x: .value("Hora", pt.date), y: .value("lpm", pt.value))
                    .foregroundStyle(hrColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.linear)
            }

            if let sel = selected {
                PointMark(x: .value("Hora", sel.date), y: .value("lpm", sel.value))
                    .foregroundStyle(hrColor)
                    .symbolSize(90)
                    .annotation(position: .top, spacing: 4) {
                        Text("\(Int(sel.value.rounded())) lpm")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(WH.Color.textPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(WH.Color.surface2, in: Capsule())
                    }
            }
        }
        .chartXScale(domain: chartStart...chartEnd)
        .chartYScale(domain: dom)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(WH.Color.separator.opacity(0.4))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(hourLabel(d))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(WH.Color.separator.opacity(0.35))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(Int(v)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                let x = g.location.x - geo[proxy.plotAreaFrame].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    selected = nearestPoint(to: date)
                                }
                            }
                            .onEnded { _ in }
                    )
            }
        }
    }

    private var legendRow: some View {
        HStack(spacing: WH.Spacing.md) {
            if let maxPt = points.max(by: { $0.value < $1.value }) {
                Text("Pico \(Int(maxPt.value.rounded())) lpm · \(hourLabel(maxPt.date))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WH.Color.recoveryRed)
            }
            if hasDataGaps {
                Text("Huecos = sin lectura del strap")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.85))
            }
            Spacer()
            Text("\(formatDuration(workout.durationS)) de sesión")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WH.Color.textSecondary)
        }
    }

    private var sessionRangeLabel: String {
        "\(hourLabel(boutStart)) – \(hourLabel(boutEnd))"
    }

    /// True when consecutive HR samples are >45 s apart (strap gap or downsampling hole).
    private var hasDataGaps: Bool {
        guard points.count >= 2 else { return false }
        let sorted = points.sorted { $0.date < $1.date }
        for i in 1..<sorted.count {
            if sorted[i].date.timeIntervalSince(sorted[i - 1].date) > 45 {
                return true
            }
        }
        return false
    }

    private var yDomain: ClosedRange<Double> {
        let vals = points.map(\.value)
        let minV = vals.min() ?? 50
        let maxV = vals.max() ?? 120
        let pad = max(8, (maxV - minV) * 0.12)
        return max(40, minV - pad)...(maxV + pad)
    }

    private func reload() async {
        isLoading = true
        let from = Int(chartStart.timeIntervalSince1970)
        let to = Int(chartEnd.timeIntervalSince1970)
        let spanSec = max(60, to - from)
        // ~1 point per 5 s of workout window (cap 1800) — avoids bucket-averaging artifacts.
        let maxPts = min(1800, max(400, spanSec / 5))
        let raw = await metrics.hrSeries(fromEpoch: from, toEpoch: to, maxPoints: maxPts)
        points = raw.filter { pt in
            pt.date >= chartStart && pt.date <= chartEnd
        }
        isLoading = false
    }

    private func nearestPoint(to date: Date) -> TrendPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func hourLabel(_ d: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: d)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let totalMin = seconds / 60
        let h = totalMin / 60
        let m = totalMin % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}
