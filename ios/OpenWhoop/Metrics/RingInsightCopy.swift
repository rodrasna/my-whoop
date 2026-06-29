import Foundation
import WhoopStore

// MARK: - RingInsightCopy
// Párrafos breves estilo WHOOP para las pantallas de detalle de anillos (Hoy → tap).

enum RingInsightCopy {

    // MARK: Sleep

    struct SleepContext {
        var efficiencyPct: Double
        var totalSleepMin: Double?
        var remPct: Double?
        var deepPct: Double?
        var regularityPct: Double?
    }

    static func sleep(_ ctx: SleepContext) -> String {
        var parts: [String] = []

        switch ctx.efficiencyPct {
        case 90...:
            parts.append("Has dormido con mucha eficiencia: el tiempo en cama se ha traducido casi por completo en sueño real.")
        case 85..<90:
            parts.append("Buen sueño reparador. La eficiencia es sólida y tu cuerpo ha descansado bien.")
        case 70..<85:
            parts.append("Sueño suficiente, aunque con algo de tiempo despierto en cama. Puede mejorar con horarios más estables.")
        default:
            parts.append("Sueño fragmentado o corto en eficiencia. Conviene revisar hora de acostarte y perturbaciones.")
        }

        if let min = ctx.totalSleepMin {
            if min >= 510 {
                parts.append("Además, has acumulado muchas horas dormidas.")
            } else if min < 360 {
                parts.append("El volumen total de sueño ha sido bajo para lo que sueles necesitar.")
            }
        }

        if let rem = ctx.remPct {
            if rem >= 22 {
                parts.append("Buena proporción de REM — sueño mentalmente reparador.")
            } else if rem < 12 {
                parts.append("Poco REM detectado esta noche (estimación con pulsera, no EEG).")
            }
        }

        if let deep = ctx.deepPct {
            if deep >= 18 {
                parts.append("Sueño profundo notable; el cuerpo ha tenido tiempo de recuperación física.")
            } else if deep < 8 {
                parts.append("Poco sueño profundo estimado — en pulsera esta etapa es la menos fiable.")
            }
        }

        if let reg = ctx.regularityPct {
            if reg >= 85 {
                parts.append("Tu horario de sueño es bastante consistente estas noches.")
            } else if reg < 70 {
                parts.append("El horario de acostarte ha sido irregular; la regularidad ayuda a la recuperación.")
            }
        }

        return parts.joined(separator: " ")
    }

    static func sleepContext(
        session: CachedSleepSession?,
        daily: DailyMetric?,
        regularityPct: Double?
    ) -> SleepContext? {
        let effPct = TodayMetricHelpers.sleepScorePercent(daily: daily, sleep: session)
        guard let efficiencyPct = effPct else { return nil }

        let totalMin = daily?.totalSleepMin
            ?? session.map { Double($0.endTs - $0.startTs) / 60 }

        var remPct: Double?
        var deepPct: Double?
        if let session, let stages = parseStages(session.stagesJSON), !stages.isEmpty {
            var d = 0.0, r = 0.0, l = 0.0
            for seg in stages {
                let m = max(0, (seg.end - seg.start) / 60)
                switch seg.stage {
                case "deep": d += m
                case "rem":  r += m
                case "light": l += m
                default: break
                }
            }
            let tst = max(d + r + l, 1)
            remPct = r / tst * 100
            deepPct = d / tst * 100
        } else if let daily {
            let tst = max((daily.deepMin ?? 0) + (daily.remMin ?? 0) + (daily.lightMin ?? 0), 1)
            if let rem = daily.remMin, rem > 0 { remPct = rem / tst * 100 }
            if let deep = daily.deepMin, deep > 0 { deepPct = deep / tst * 100 }
        }

        return SleepContext(
            efficiencyPct: efficiencyPct,
            totalSleepMin: totalMin,
            remPct: remPct,
            deepPct: deepPct,
            regularityPct: regularityPct
        )
    }

    // MARK: Recovery

    static func recovery(percent: Double, provisional: Bool) -> String {
        let base: String
        switch percent {
        case 67...:
            base = "Tu cuerpo está bien recuperado. Buen día para exigirte si lo necesitas."
        case 34..<67:
            base = "Recuperación moderada. Puedes entrenar, pero escucha la fatiga y no te pases de intensidad."
        default:
            base = "Recuperación baja. Prioriza sueño, hidratación y carga ligera; el cuerpo pide descanso."
        }
        if provisional {
            return base + " Este porcentaje es provisional hasta que lleves unas noches calibrando tu baseline."
        }
        return base
    }

    // MARK: Strain

    static func strain(_ strain: Double) -> String {
        let pct = WH.Ring.strainPercent(strain)
        switch strain {
        case 16...:
            return "Has exigido mucho al cuerpo hoy (\(pct)% del máximo). Planifica recuperación activa y buen sueño."
        case 11..<16:
            return "Día de carga alta (\(pct)%). Encaja con un entreno intenso; vigila la acumulación mañana."
        case 6..<11:
            return "Esfuerzo moderado (\(pct)%). Buen equilibrio entre actividad y recuperación."
        default:
            return "Día ligero en esfuerzo (\(pct)%). Ideal para recuperar o moverte sin mucha intensidad."
        }
    }
}
