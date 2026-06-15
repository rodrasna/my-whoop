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
            zonePct: zones
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
            zonePct: (0...5).map { w.zoneTimePct[$0] ?? 0.0 }
        )
    }

    struct Features {
        let startHour: Int
        let weekday: Int
        let durationMin: Double
        let avgHr: Double
        let zonePct: [Double]
    }

    var features: Features {
        Features(startHour: startHour, weekday: weekday,
                 durationMin: durationMin, avgHr: avgHr, zonePct: zonePct)
    }

    /// Distancia entre dos firmas en [0, ~1+]. Combina rutina (hora/día) e intensidad
    /// (duración, FC, reparto por zonas). Pensada para k-NN con pocos datos.
    static func distance(_ a: Features, _ b: Features) -> Double {
        // Hora: circular sobre 24h → 0..1
        let rawHour = Double(abs(a.startHour - b.startHour))
        let hourDist = min(rawHour, 24 - rawHour) / 12.0
        // Día de semana: mismo día = 0, distinto = 1
        let dayDist: Double = a.weekday == b.weekday ? 0 : 1
        // Duración: |Δ|/30min, cap 1
        let durDist = min(abs(a.durationMin - b.durationMin) / 30.0, 1.0)
        // FC media: |Δ|/30 lpm, cap 1
        let hrDist = min(abs(a.avgHr - b.avgHr) / 30.0, 1.0)
        // Reparto por zonas: suma de |Δ%|/100, normalizado a 0..1
        let zoneDist = min(zip(a.zonePct, b.zonePct).reduce(0.0) { $0 + abs($1.0 - $1.1) } / 100.0, 1.0)
        // Pesos: la rutina manda; la firma de intensidad afina.
        return 0.35 * hourDist + 0.20 * dayDist + 0.15 * durDist + 0.10 * hrDist + 0.20 * zoneDist
    }
}
