import SwiftUI
import WhoopStore

// MARK: - SleepZoneGauge
// Barra de 3 zonas estilo WHOOP (deficiente · suficiente · óptimo) con marcador sobre la barra
// y leyenda inferior.

struct SleepZoneGauge: View {
    var value: Double
    var lowCutoff: Double = 70
    var highCutoff: Double = 85

    private var clamped: Double { min(100, max(0, value)) }

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            GeometryReader { geo in
                let w = geo.size.width
                let lowW = w * CGFloat(lowCutoff / 100)
                let midW = w * CGFloat((highCutoff - lowCutoff) / 100)
                let highW = w - lowW - midW
                let markerX = w * CGFloat(clamped / 100)

                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        zoneSegment(width: lowW, color: WH.Color.stressHigh.opacity(0.88))
                        zoneSegment(width: midW, color: WH.Color.textSecondary.opacity(0.38))
                        zoneSegment(width: highW, color: WH.Color.recoveryGreen.opacity(0.92))
                    }
                    .frame(height: 10)
                    .clipShape(Capsule())

                    Capsule()
                        .fill(WH.Color.textPrimary)
                        .frame(width: 4, height: 20)
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        .offset(x: max(0, min(w - 4, markerX - 2)), y: -5)
                }
            }
            .frame(height: 20)

            HStack {
                zoneLegend("Deficiente", color: WH.Color.stressHigh)
                Spacer(minLength: WH.Spacing.xs)
                zoneLegend("Suficiente", color: WH.Color.textSecondary)
                Spacer(minLength: WH.Spacing.xs)
                zoneLegend("Óptimo", color: WH.Color.recoveryGreen)
            }
        }
    }

    private func zoneSegment(width: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(0, width))
    }

    private func zoneLegend(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
        }
    }
}

// MARK: - SleepQualityMetricsCard
// Tarjeta bajo el anillo hero — sub-métricas con barras de zona (estilo WHOOP).

struct SleepQualityMetricsCard: View {
    struct Row: Identifiable {
        let id: String
        let title: String
        let value: String
        let context: String?
        let gaugeValue: Double
    }

    var rows: [Row]

    var body: some View {
        if rows.isEmpty { EmptyView() }
        else {
            VStack(alignment: .leading, spacing: 0) {
                pointerTail

                VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(WH.Color.separator.opacity(0.35))
                                .frame(height: 0.5)
                        }
                        metricBlock(row)
                    }
                }
                .padding(WH.Spacing.md)
                .background(WH.Color.surface,
                            in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            }
        }
    }

    private var pointerTail: some View {
        HStack {
            Spacer()
            CardPointer()
                .fill(WH.Color.surface)
                .frame(width: 18, height: 10)
            Spacer()
        }
        .offset(y: 1)
    }

    private func metricBlock(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                Spacer(minLength: WH.Spacing.sm)
                Text(row.value)
                    .font(.system(size: 17, weight: .heavy, design: .default))
                    .fontWidth(.condensed)
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
            }
            if let ctx = row.context {
                Text(ctx)
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }
            SleepZoneGauge(value: row.gaugeValue)
        }
    }
}

private struct CardPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Sleep quality helpers

enum SleepQualityBuilder {

    /// 0–100: menor variación de hora de acostarse = mayor regularidad.
    static func regularityScore(from sessions: [CachedSleepSession]) -> Double? {
        let nights = sessions.filter { $0.isMainNight }
        let pool = nights.isEmpty ? sessions.filter { !$0.isNap } : nights
        guard pool.count >= 3 else { return nil }
        let cal = Calendar.current
        let minutes: [Double] = pool.map { session in
            let d = Date(timeIntervalSince1970: TimeInterval(session.startTs))
            let c = cal.dateComponents([.hour, .minute], from: d)
            return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        let mean = minutes.reduce(0, +) / Double(minutes.count)
        let variance = minutes.map { pow($0 - mean, 2) }.reduce(0, +) / Double(minutes.count)
        let stdDev = sqrt(variance)
        return max(0, min(100, 100 - stdDev * 1.1))
    }

    static func regularityContext(score: Double, nights: Int) -> String {
        if nights < 3 {
            return "Necesitas al menos 3 noches para medir consistencia"
        }
        if score < 5 {
            return "Horarios de acostarte muy distintos entre noches (o sesiones erróneas en el historial)"
        }
        let band: String = {
            if score >= 85 { return "Horario muy consistente" }
            if score >= 70 { return "Razonablemente regular" }
            return "Horario irregular"
        }()
        return "\(band) · \(nights) noches · \(Int(score.rounded()))% consistencia"
    }
}
