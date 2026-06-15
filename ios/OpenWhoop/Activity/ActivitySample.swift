import Foundation
import WhoopStore

// MARK: - ActivitySample
// Una muestra de referencia: la firma de un entreno + la etiqueta que le puso el usuario.
// Es el dato de entrenamiento que acumulamos al etiquetar, para que más adelante un
// clasificador (k-NN) reconozca el tipo de actividad automáticamente. La banda NO sabe
// el deporte; lo aprende de estas muestras etiquetadas por ti.

struct ActivitySample: Codable, Identifiable {
    let workoutId: String
    let label: String          // ActivityType.rawValue
    let recordedTs: Int        // cuándo se etiquetó

    // Firma (features) — capturada en el momento de etiquetar.
    let startHour: Int         // 0-23, hora local
    let weekday: Int           // 1-7 (Calendar.current)
    let durationMin: Double
    let avgHr: Double
    let peakHr: Double
    let avgHrrPct: Double?
    let zonePct: [Double]      // 6 valores (Z0..Z5), % de tiempo
    let motionVar: Double?     // varianza de movimiento (firma del servidor)
    let hrPeaksPerMin: Double? // picos de FC por minuto (estructura de intervalos)

    var id: String { workoutId }

    var type: ActivityType? { ActivityType(rawValue: label) }

    /// Construye la firma a partir de un entreno y la etiqueta asignada.
    static func make(from w: Workout, label: ActivityType, now: Date = Date()) -> ActivitySample {
        let cal = Calendar.current
        let start = Date(timeIntervalSince1970: TimeInterval(w.startTs))
        let zones = (0...5).map { w.zoneTimePct[$0] ?? 0.0 }
        return ActivitySample(
            workoutId: w.id,
            label: label.rawValue,
            recordedTs: Int(now.timeIntervalSince1970),
            startHour: cal.component(.hour, from: start),
            weekday: cal.component(.weekday, from: start),
            durationMin: Double(w.durationS) / 60.0,
            avgHr: w.avgHr,
            peakHr: Double(w.peakHr),
            avgHrrPct: w.avgHrrPct,
            zonePct: zones,
            motionVar: w.motionVar,
            hrPeaksPerMin: w.hrPeaksPerMin
        )
    }

    /// Vector de features de un entreno (sin etiqueta), para comparar contra las muestras.
    static func features(of w: Workout) -> Features {
        let cal = Calendar.current
        let start = Date(timeIntervalSince1970: TimeInterval(w.startTs))
        return Features(
            startHour: cal.component(.hour, from: start),
            weekday: cal.component(.weekday, from: start),
            durationMin: Double(w.durationS) / 60.0,
            avgHr: w.avgHr,
            zonePct: (0...5).map { w.zoneTimePct[$0] ?? 0.0 },
            motionVar: w.motionVar,
            hrPeaksPerMin: w.hrPeaksPerMin
        )
    }

    struct Features {
        let startHour: Int
        let weekday: Int
        let durationMin: Double
        let avgHr: Double
        let zonePct: [Double]
        let motionVar: Double?
        let hrPeaksPerMin: Double?
    }

    var features: Features {
        Features(startHour: startHour, weekday: weekday,
                 durationMin: durationMin, avgHr: avgHr, zonePct: zonePct,
                 motionVar: motionVar, hrPeaksPerMin: hrPeaksPerMin)
    }

    /// Distancia entre dos firmas en [0, 1]. Combina rutina (hora/día) e intensidad
    /// (duración, FC, zonas) y, cuando el servidor las aporta, la firma de movimiento
    /// (varianza de movimiento, picos de FC/min). Cada término solo cuenta si ambas
    /// muestras lo tienen; los pesos se renormalizan sobre los términos presentes,
    /// así que la distancia es comparable haya o no datos de movimiento.
    static func distance(_ a: Features, _ b: Features) -> Double {
        var sum = 0.0
        var wsum = 0.0
        func add(_ weight: Double, _ d: Double) { sum += weight * min(d, 1.0); wsum += weight }

        // Hora: circular sobre 24h → 0..1
        let rawHour = Double(abs(a.startHour - b.startHour))
        add(0.30, min(rawHour, 24 - rawHour) / 12.0)
        // Día de semana: mismo día = 0, distinto = 1
        add(0.18, a.weekday == b.weekday ? 0 : 1)
        // Duración: |Δ|/30min
        add(0.12, abs(a.durationMin - b.durationMin) / 30.0)
        // FC media: |Δ|/30 lpm
        add(0.10, abs(a.avgHr - b.avgHr) / 30.0)
        // Reparto por zonas: suma de |Δ%|/100
        add(0.15, zip(a.zonePct, b.zonePct).reduce(0.0) { $0 + abs($1.0 - $1.1) } / 100.0)
        // Firma de movimiento (opcional): varianza de movimiento y picos de FC/min.
        if let av = a.motionVar, let bv = b.motionVar {
            add(0.08, abs(av - bv) / 1.0)
        }
        if let ap = a.hrPeaksPerMin, let bp = b.hrPeaksPerMin {
            add(0.07, abs(ap - bp) / 1.0)
        }
        return wsum > 0 ? sum / wsum : 1.0
    }
}
