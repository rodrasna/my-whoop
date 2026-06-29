import SwiftUI
import Charts

// MARK: - StressMonitorCard
// Intraday stress curve (0–3) from server-computed RMSSD + HR windows.

struct StressMonitorCard: View {
    var completedNights: Int
    var requiredNights: Int = 4
    var sleepStartTs: Int?
    var sleepEndTs: Int?
    var points: [StressPoint] = []

    private var scoredPoints: [StressPoint] {
        points.filter(\.isScored).sorted { $0.ts < $1.ts }
    }

    private var isCalibrating: Bool {
        scoredPoints.count < 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            headerRow
            ZStack(alignment: .bottomLeading) {
                stressZoneBands
                sleepBandOverlay
                chartContent
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            statusBanner
        }
    }

    private var peakPoint: StressPoint? {
        scoredPoints.max { ($0.score ?? 0) < ($1.score ?? 0) }
    }

    private var headerRow: some View {
        HStack {
            Text("MONITOR DE ESTRÉS")
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)
            Spacer()
            if let peak = scoredPoints.compactMap(\.score).max() {
                Text(String(format: "Pico %.1f", peak).replacingOccurrences(of: ".", with: ","))
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.stressHigh)
            }
        }
    }

    private var statusBanner: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text(isCalibrating ? "Calibrando baseline" : stressLevelTitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            Text(statusMessage)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !isCalibrating, scoredPoints.count >= 2 {
                stressLegend
            }
        }
        .padding(WH.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.surface2,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private var stressLevelTitle: String {
        guard let avg = averageScore else { return "Estrés diurno" }
        switch avg {
        case ..<1.0: return "Estrés bajo hoy"
        case ..<2.0: return "Estrés moderado"
        default: return "Estrés elevado"
        }
    }

    private var averageScore: Double? {
        let vals = scoredPoints.compactMap(\.score)
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private var stressLegend: some View {
        HStack(spacing: WH.Spacing.sm) {
            legendChip("0–1 bajo", color: WH.Color.stressLow)
            legendChip("1–2 medio", color: WH.Color.stressMedium)
            legendChip("2–3 alto", color: WH.Color.stressHigh)
        }
        .padding(.top, WH.Spacing.xs)
    }

    private func legendChip(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WH.Color.textSecondary)
        }
    }

    private var statusMessage: String {
        if isCalibrating {
            if scoredPoints.isEmpty {
                return "Necesitamos varios días con ventanas en reposo (HRV + FC) para tu baseline personal. "
                    + "Llevas \(completedNights) noches de sueño sincronizadas."
            }
            return "Baseline en construcción (\(scoredPoints.count) ventanas hoy). "
                + "Sigue usando la pulsera en reposo; la curva se afina en unos días."
        }
        if let peak = peakPoint, let s = peak.score {
            let t = timeLabel(peak.ts)
            let band = s < 1 ? "bajo" : (s < 2 ? "moderado" : "alto")
            if let avg = averageScore {
                return "Pico \(band) a las \(t). Media del día: \(formatScore(avg))."
            }
            return "Pico \(band) a las \(t)."
        }
        return "Curva de reposo (HRV + FC vs tu baseline). Entrenos y movimiento no cuentan."
    }

    private func formatScore(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    @ViewBuilder
    private var chartContent: some View {
        if scoredPoints.count >= 2, let domain = dayDomain {
            Chart {
                ForEach(scoredPoints) { p in
                    if let score = p.score {
                        let when = Date(timeIntervalSince1970: TimeInterval(p.ts))
                        AreaMark(
                            x: .value("Hora", when),
                            y: .value("Estrés", score)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    WH.Color.textPrimary.opacity(0.22),
                                    WH.Color.textPrimary.opacity(0.02),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Hora", when),
                            y: .value("Estrés", score)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(WH.Color.textPrimary.opacity(0.92))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .chartYScale(domain: 0...3)
            .chartXScale(domain: domain)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(hourLabel(date))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(WH.Color.textSecondary.opacity(0.85))
                        }
                    }
                }
            }
            .padding(.horizontal, WH.Spacing.sm)
            .padding(.top, WH.Spacing.xs)
            .padding(.bottom, 2)
        } else {
            VStack {
                Spacer()
                HStack(spacing: WH.Spacing.sm) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
                    Text(scoredPoints.isEmpty
                         ? "Sin lecturas de estrés este día"
                         : "Pocas lecturas — sigue calibrando")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                }
                .padding(WH.Spacing.md)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var dayDomain: ClosedRange<Date>? {
        guard let ref = points.first?.ts ?? sleepEndTs else { return nil }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(ref)))
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        return dayStart...dayEnd
    }

    private func timeLabel(_ ts: Int) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private func hourLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "H"
        return fmt.string(from: date) + "h"
    }

    private var stressZoneBands: some View {
        VStack(spacing: 0) {
            band(height: 40, color: WH.Color.stressHigh.opacity(0.12))
            band(height: 40, color: WH.Color.stressMedium.opacity(0.10))
            band(height: 40, color: WH.Color.stressLow.opacity(0.14))
        }
    }

    private func band(height: CGFloat, color: Color) -> some View {
        Rectangle().fill(color).frame(height: height)
    }

    @ViewBuilder
    private var sleepBandOverlay: some View {
        if let start = sleepStartTs, let end = sleepEndTs, end > start {
            GeometryReader { geo in
                let (x, w) = sleepBandFraction(start: start, end: end, width: geo.size.width)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(WH.Color.sleepBlue.opacity(0.22))
                        .frame(width: w, height: geo.size.height - 8)
                        .offset(x: x, y: 4)
                    Image(systemName: "moon.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WH.Color.sleepBlue.opacity(0.9))
                        .offset(x: x + 6, y: 8)
                }
            }
        }
    }

    private func sleepBandFraction(start: Int, end: Int, width: CGFloat) -> (x: CGFloat, w: CGFloat) {
        let cal = Calendar.current
        let endDate = Date(timeIntervalSince1970: TimeInterval(end))
        let dayStart = cal.startOfDay(for: endDate)
        let dayStartTs = dayStart.timeIntervalSince1970
        let daySpan: CGFloat = 86_400
        let xFrac = CGFloat(max(0, Double(start) - dayStartTs) / Double(daySpan))
        let wFrac = CGFloat(min(1, Double(end - start) / Double(daySpan)))
        return (xFrac * width, max(8, wFrac * width))
    }
}

#Preview {
    StressMonitorCard(
        completedNights: 6,
        sleepStartTs: 1_700_000_000,
        sleepEndTs: 1_700_026_000,
        points: [
            StressPoint(ts: 1_700_010_000, score: 1.1, quality: "good"),
            StressPoint(ts: 1_700_011_000, score: 1.8, quality: "good"),
            StressPoint(ts: 1_700_012_000, score: 2.2, quality: "good"),
        ]
    )
    .padding()
    .background(WH.Color.background)
}
