import SwiftUI
import Charts
import WhoopStore

// MARK: - SleepTempChartView
// Per-night skin-temperature DEVIATION trend (Δ°C over time), bounded to a sleep
// session's window. The series comes from the server's /v1/temp-series endpoint,
// which reads raw ADC counts from skin_temp_samples and returns each sample's
// deviation from the within-night median ADC, scaled by the un-calibrated slope
// (0.02 °C/count). The additive offset cancels in the deviation so absolute
// accuracy is not required. Values are NOT absolute °C — see footnote. iOS 16-safe.

struct SleepTempChartView: View {

    @EnvironmentObject private var metrics: MetricsRepository

    let session: CachedSleepSession

    @State private var points: [TrendPoint] = []
    @State private var isLoading = true
    @State private var selected: TrendPoint? = nil

    private struct Stats { let avg: Double; let min: Double; let max: Double }

    private var stats: Stats? {
        guard !points.isEmpty else { return nil }
        let vals = points.map(\.value)
        return Stats(avg: vals.reduce(0, +) / Double(vals.count),
                     min: vals.min()!,
                     max: vals.max()!)
    }

    // Color: recoveryYellow (#FFDE00) — tono cálido/ámbar coherente con temperatura
    private var tempColor: Color { WH.Color.recoveryYellow }

    var body: some View {
        ZStack {
            WH.Color.background.ignoresSafeArea()
            if isLoading {
                loadingView
            } else {
                scrollContent
            }
        }
        .navigationTitle("Temperatura de piel durante el sueño")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { await reload() }
    }

    private var loadingView: some View {
        VStack(spacing: WH.Spacing.md) {
            ProgressView().tint(WH.Color.textSecondary)
            Text("Cargando temperatura…")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                windowHeader
                if let s = stats { statsStrip(s) }
                chartSection
                footnote
                Spacer(minLength: WH.Spacing.xl)
            }
            .padding(WH.Spacing.md)
        }
        .background(WH.Color.background)
    }

    private var windowHeader: some View {
        HStack {
            Text(timeLabel(session.startTs) + " → " + timeLabel(session.endTs))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            Spacer()
        }
    }

    private func statsStrip(_ s: Stats) -> some View {
        HStack(spacing: 0) {
            statCell(label: "MEDIA", value: String(format: "%+.2f", s.avg))
            Divider().frame(height: 32).background(WH.Color.separator)
            statCell(label: "MÍN", value: String(format: "%+.2f", s.min))
            Divider().frame(height: 32).background(WH.Color.separator)
            statCell(label: "MÁX", value: String(format: "%+.2f", s.max))
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: WH.Spacing.xs) {
            Text(label)
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.0)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(tempColor)
                    .monospacedDigit()
                Text("Δ°C")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var chartSection: some View {
        if points.count < 2 {
            noDataCard
        } else {
            Chart {
                // Línea de referencia en 0 (mediana de la noche)
                RuleMark(y: .value("Referencia", 0.0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(WH.Color.separator)

                ForEach(points) { pt in
                    AreaMark(x: .value("Hora", pt.date), y: .value("Δ°C", pt.value))
                        .foregroundStyle(LinearGradient(
                            colors: [tempColor.opacity(0.28), tempColor.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                }
                ForEach(points) { pt in
                    LineMark(x: .value("Hora", pt.date), y: .value("Δ°C", pt.value))
                        .foregroundStyle(tempColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                }
                if let sel = selected {
                    PointMark(x: .value("Hora", sel.date), y: .value("Δ°C", sel.value))
                        .foregroundStyle(tempColor)
                        .symbolSize(100)
                        .annotation(position: .top, alignment: .center, spacing: 4) {
                            callout(sel)
                        }
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(WH.Color.separator.opacity(0.5))
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
                    AxisGridLine().foregroundStyle(WH.Color.separator)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%+.1f", v))
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(WH.Color.textSecondary)
                        }
                    }
                }
            }
            .chartPlotStyle { plot in plot.background(WH.Color.surface2).clipped() }
            .clipped()
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .onTapGesture { location in handleTap(location, proxy, geo) }
                }
            }
            .frame(height: 260)
            .padding(WH.Spacing.xs)
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
    }

    private var noDataCard: some View {
        HStack {
            Spacer()
            VStack(spacing: WH.Spacing.xs) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
                Text("Sin datos de temperatura de piel para esta noche")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(height: 200)
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func callout(_ pt: TrendPoint) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%+.2f Δ°C", pt.value))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            Text(timeLabel(Int(pt.date.timeIntervalSince1970)))
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(WH.Color.textSecondary)
        }
        .padding(.horizontal, WH.Spacing.sm)
        .padding(.vertical, WH.Spacing.xs)
        .background(WH.Color.surface2,
                    in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous)
            .stroke(WH.Color.separator, lineWidth: 0.5))
    }

    private var footnote: some View {
        Text("Desviación de temperatura de piel respecto a la mediana de la propia noche (Δ°C). No se muestran grados absolutos: la calibración del termistor es propietaria de WHOOP. Este valor relativo refleja cambios circadianos durante el sueño, como hace la app oficial.")
            .font(WH.Font.caption)
            .foregroundStyle(WH.Color.textSecondary.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var yDomain: ClosedRange<Double> {
        let vals = points.map(\.value)
        let lo = (vals.min() ?? -1.0) - 0.5
        let hi = (vals.max() ?? 1.0)  + 0.5
        return lo...hi
    }

    private func handleTap(_ location: CGPoint, _ proxy: ChartProxy, _ geo: GeometryProxy) {
        guard !points.isEmpty else { return }
        let origin = geo[proxy.plotAreaFrame].origin
        let x = location.x - origin.x
        if let date: Date = proxy.value(atX: x) {
            selected = points.min(by: {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            })
        }
    }

    private func timeLabel(_ epoch: Int) -> String {
        Self.timeFmt.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    private func hourLabel(_ date: Date) -> String { Self.timeFmt.string(from: date) }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private func reload() async {
        isLoading = true
        points = await metrics.tempSeries(fromEpoch: session.startTs, toEpoch: session.endTs)
        isLoading = false
    }
}
