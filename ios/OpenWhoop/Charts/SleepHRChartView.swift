import SwiftUI
import Charts
import WhoopStore

// MARK: - SleepHRChartView
// Per-night heart-rate evolution: loads the downsampled HR stream bounded to a single
// sleep session's window (startTs → endTs) and plots it with a time-of-day x-axis.
// This is the only in-sleep signal with a real per-timestamp series; HRV is a nightly
// scalar and resp/SpO2/skin-temp are stored only as uncalibrated raw ADC, so they
// don't get a chart (a line there would misrepresent the values).
// iOS 16-safe.

struct SleepHRChartView: View {

    @EnvironmentObject private var metrics: MetricsRepository

    let session: CachedSleepSession

    @State private var points: [TrendPoint] = []
    @State private var isLoading = true
    @State private var selected: TrendPoint? = nil

    // MARK: - Stats

    private struct Stats { let avg: Double; let min: Double; let max: Double }

    private var stats: Stats? {
        guard !points.isEmpty else { return nil }
        let vals = points.map(\.value)
        return Stats(avg: vals.reduce(0, +) / Double(vals.count),
                     min: vals.min()!,
                     max: vals.max()!)
    }

    private var hrColor: Color { MetricKind.rawHR.color }

    // MARK: - Body

    var body: some View {
        ZStack {
            WH.Color.background.ignoresSafeArea()
            if isLoading {
                loadingView
            } else {
                scrollContent
            }
        }
        .navigationTitle("FC durante el sueño")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { await reload() }
    }

    private var loadingView: some View {
        VStack(spacing: WH.Spacing.md) {
            ProgressView().tint(WH.Color.textSecondary)
            Text("Cargando frecuencia cardíaca…")
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

    // MARK: - Window header

    private var windowHeader: some View {
        HStack {
            Text(timeLabel(session.startTs) + " → " + timeLabel(session.endTs))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            Spacer()
        }
    }

    // MARK: - Stats strip

    private func statsStrip(_ s: Stats) -> some View {
        HStack(spacing: 0) {
            statCell(label: "MEDIA", value: String(Int(s.avg.rounded())))
            Divider().frame(height: 32).background(WH.Color.separator)
            statCell(label: "MÍN", value: String(Int(s.min.rounded())))
            Divider().frame(height: 32).background(WH.Color.separator)
            statCell(label: "MÁX", value: String(Int(s.max.rounded())))
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
                    .foregroundStyle(hrColor)
                    .monospacedDigit()
                Text("lpm")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartSection: some View {
        if points.count < 2 {
            noDataCard
        } else {
            Chart {
                ForEach(points) { pt in
                    AreaMark(x: .value("Hora", pt.date), y: .value("lpm", pt.value))
                        .foregroundStyle(LinearGradient(
                            colors: [hrColor.opacity(0.28), hrColor.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                }
                ForEach(points) { pt in
                    LineMark(x: .value("Hora", pt.date), y: .value("lpm", pt.value))
                        .foregroundStyle(hrColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                }
                if let sel = selected {
                    PointMark(x: .value("Hora", sel.date), y: .value("lpm", sel.value))
                        .foregroundStyle(hrColor)
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
                            Text(String(Int(v)))
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
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
                Text("Sin muestras de FC para esta noche")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }
            Spacer()
        }
        .frame(height: 200)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func callout(_ pt: TrendPoint) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(pt.value.rounded())) lpm")
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
        Text("Tu pulso a lo largo de la noche. Suele bajar en el sueño profundo y repuntar en REM o al despertar.")
            .font(WH.Font.caption)
            .foregroundStyle(WH.Color.textSecondary.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Helpers

    private var yDomain: ClosedRange<Double> {
        let vals = points.map(\.value)
        let lo = (vals.min() ?? 40) - 5
        let hi = (vals.max() ?? 90) + 5
        return max(0, lo)...hi
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

    private func hourLabel(_ date: Date) -> String { Self.hourFmt.string(from: date) }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let hourFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    // MARK: - Data

    private func reload() async {
        isLoading = true
        points = await metrics.hrSeries(fromEpoch: session.startTs,
                                        toEpoch: session.endTs,
                                        maxPoints: 300)
        isLoading = false
    }
}
