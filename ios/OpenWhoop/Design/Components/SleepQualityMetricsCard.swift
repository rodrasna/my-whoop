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

    struct RegularityStats {
        let score: Double
        let stdDevMinutes: Double
        let nightCount: Int
    }

    /// 0–100: menor variación de hora de acostarte = mayor puntuación (estilo WHOOP «sleep consistency»).
    static func regularityStats(from sessions: [CachedSleepSession]) -> RegularityStats? {
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
        let score = max(0, min(100, 100 - stdDev * 1.1))
        return RegularityStats(score: score, stdDevMinutes: stdDev, nightCount: pool.count)
    }

    static func regularityScore(from sessions: [CachedSleepSession]) -> Double? {
        regularityStats(from: sessions)?.score
    }

    static func regularityContext(stats: RegularityStats) -> String {
        if stats.nightCount < 3 {
            return "Necesitas al menos 3 noches para medir consistencia"
        }
        if stats.score < 5 {
            return "Horarios de acostarte muy distintos entre noches (o sesiones erróneas en el historial)"
        }
        let band: String = {
            if stats.score >= 85 { return "Horario muy consistente" }
            if stats.score >= 70 { return "Razonablemente regular" }
            return "Horario irregular"
        }()
        let dev = Int(stats.stdDevMinutes.rounded())
        return "\(band) · \(stats.nightCount) noches · ±\(dev) min de variación al acostarte"
    }

    static func metricRows(
        daily: DailyMetric?,
        weekNights: [CachedSleepSession],
        subjectiveFeeling: Double? = nil,
        alignment: String? = nil
    ) -> [SleepQualityMetricsCard.Row] {
        guard let daily else { return [] }
        var rows: [SleepQualityMetricsCard.Row] = []
        let breakdown = daily.sleepScoreBreakdown
        let needMin = breakdown?.sleepNeedMin ?? 480

        if let final = daily.sleepScore ?? breakdown?.final {
            rows.append(.init(
                id: "final",
                title: "Calidad del sueño",
                value: "\(Int(final.rounded()))%",
                context: breakdown?.provisional == true
                    ? "Provisional · mejora con más noches"
                    : "Score compuesto (pulsera + cuestionario)",
                gaugeValue: final
            ))
        }

        let components = breakdown?.components
        if let qty = components?.quantity {
            let slept = daily.totalSleepMin ?? 0
            let needH = needMin / 60
            let sleptH = slept / 60
            rows.append(.init(
                id: "quantity",
                title: "Cantidad vs. necesidad",
                value: String(format: "%.1fh / %.1fh", sleptH, needH),
                context: qty >= 100 ? "Cumples tu necesidad personal" : "Por debajo de tu necesidad habitual",
                gaugeValue: qty
            ))
        } else if let slept = daily.totalSleepMin, slept > 0 {
            let pct = min(100, slept / needMin * 100)
            rows.append(.init(
                id: "hours",
                title: "Horas vs. lo necesario",
                value: formatMinutesStatic(slept, needMin: needMin),
                context: pct >= 100 ? "Cumples el objetivo de sueño" : "Por debajo de tu necesidad",
                gaugeValue: pct
            ))
        }

        if let eff = components?.efficiency ?? daily.efficiency.map({ $0 * 100 }) {
            rows.append(.init(
                id: "efficiency",
                title: "Eficiencia",
                value: "\(Int(eff.rounded()))%",
                context: "Tiempo dormido vs. tiempo en cama",
                gaugeValue: eff
            ))
        }

        if let arch = components?.architecture {
            rows.append(.init(
                id: "architecture",
                title: "Calidad arquitectural",
                value: "\(Int(arch.rounded()))%",
                context: "Despertares, latencia y balance de fases (estimado)",
                gaugeValue: arch
            ))
        }

        if let cons = components?.consistency {
            rows.append(.init(
                id: "regularity",
                title: "Consistencia horaria",
                value: "\(Int(cons.rounded()))%",
                context: "Regularidad de hora de acostarte",
                gaugeValue: cons
            ))
        } else if let stats = regularityStats(from: weekNights) {
            rows.append(.init(
                id: "regularity",
                title: "Consistencia horaria",
                value: "\(Int(stats.score.rounded()))%",
                context: regularityContext(stats: stats),
                gaugeValue: stats.score
            ))
        }

        if let feeling = subjectiveFeeling ?? breakdown?.subjective {
            rows.append(.init(
                id: "subjective",
                title: "Tu sensación",
                value: "\(Int(feeling.rounded()))%",
                context: alignmentLabel(alignment),
                gaugeValue: feeling
            ))
        }

        return rows
    }

    private static func formatMinutesStatic(_ minutes: Double, needMin: Double) -> String {
        func fmt(_ m: Double) -> String {
            let h = Int(m) / 60
            let min = Int(m) % 60
            return min > 0 ? "\(h)h \(min)m" : "\(h)h"
        }
        return "\(fmt(minutes)) / \(fmt(needMin))"
    }

    private static func alignmentLabel(_ alignment: String?) -> String? {
        switch alignment {
        case "strap_higher": return "La pulsera dice mejor noche de la que sentiste"
        case "body_higher": return "Te sientes mejor que lo que marca la pulsera"
        case "aligned": return "Encaja con las métricas de la pulsera"
        default: return "Cuestionario matutino"
        }
    }
}
