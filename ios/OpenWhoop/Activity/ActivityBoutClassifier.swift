import Foundation

// MARK: - ActivityBoutClassifier
// Heurísticas en el cliente para separar entrenos reales de picos de FC / rutinas diarias
// (p. ej. despertar ~7:05 cada día). El servidor detecta "bouts" por FC+motion; aquí
// refinamos qué mostramos y cómo lo etiquetamos.

enum BoutCategory: String, Equatable {
    /// Strain alto, intensidad sostenida, o confirmado por el usuario.
    case likelyWorkout
    /// FC elevada pero dudoso (bajo strain, poca zona 2+).
    case hrSpike
    /// Mismo horario varios días de la semana — rutina matutina, desplazamiento, etc.
    case dailyRoutine
    /// Marcado por el usuario como actividad cotidiana (caminata, rutina, etc.), no entreno.
    case lifeActivity

    var listTitle: String {
        switch self {
        case .likelyWorkout:  return "Entreno probable"
        case .hrSpike:        return "Pico de FC"
        case .dailyRoutine:   return "Rutina diaria"
        case .lifeActivity:   return "Actividad"
        }
    }

    var icon: String {
        switch self {
        case .likelyWorkout:  return "figure.run"
        case .hrSpike:        return "waveform.path.ecg"
        case .dailyRoutine:   return "sunrise.fill"
        case .lifeActivity:   return "figure.walk"
        }
    }

    /// Cuenta en el resumen deportivo semanal.
    var countsAsWorkout: Bool {
        self == .likelyWorkout
    }
}

struct BoutAssessment: Equatable {
    let category: BoutCategory
    let reason: String
}

enum ActivityBoutClassifier {

    /// Evalúa un bout respecto al histórico reciente y las decisiones del usuario.
    static func assess(
        _ workout: Workout,
        among all: [Workout],
        isConfirmed: Bool,
        isDismissed: Bool
    ) -> BoutAssessment {
        if isDismissed {
            return BoutAssessment(
                category: .lifeActivity,
                reason: "Actividad con FC elevada — no cuenta como entreno en tu resumen"
            )
        }
        if workout.kind == "hr_elevation" {
            let hour = localHour(workout.startTs)
            if hour >= 5 && hour < 11 {
                return BoutAssessment(
                    category: .dailyRoutine,
                    reason: "Subida de FC al despertar — revisa el gráfico y clasifica si fue entreno"
                )
            }
            return BoutAssessment(
                category: .hrSpike,
                reason: "Subida de FC detectada — revisa el gráfico y clasifica si fue entreno"
            )
        }
        if isConfirmed {
            return BoutAssessment(category: .likelyWorkout, reason: "Clasificado por ti")
        }

        let strain = workout.strain ?? 0
        let z2 = zone2PlusPct(workout)
        let hour = localHour(workout.startTs)
        let routineDays = recurringDayCount(for: workout, in: all)

        if routineDays >= 3 {
            let t = localTimeString(workout.startTs)
            return BoutAssessment(
                category: .dailyRoutine,
                reason: "Patrón repetido ~\(t) en \(routineDays) días — probable rutina, no entreno"
            )
        }

        if hour >= 5 && hour < 10 {
            if strain < 7 && z2 < 50 {
                return BoutAssessment(
                    category: .dailyRoutine,
                    reason: "Por la mañana con poco esfuerzo sostenido — suele ser despertar o actividad ligera"
                )
            }
        }

        if strain >= 8 || z2 >= 55 {
            return BoutAssessment(
                category: .likelyWorkout,
                reason: "Esfuerzo o intensidad cardíaca sostenida"
            )
        }

        if workout.durationS >= 20 * 60 && z2 >= 45 {
            return BoutAssessment(
                category: .likelyWorkout,
                reason: "Duración e intensidad compatibles con ejercicio"
            )
        }

        if workout.peakHr >= 150 && strain < 5 {
            return BoutAssessment(
                category: .hrSpike,
                reason: "Pico de FC (\(workout.peakHr) lpm) sin esfuerzo acumulado — revisa el gráfico"
            )
        }

        return BoutAssessment(
            category: .hrSpike,
            reason: "FC elevada sin señales claras de entreno — confirma o descarta"
        )
    }

    static func zone2PlusPct(_ w: Workout) -> Double {
        (2...5).reduce(0.0) { $0 + (w.zoneTimePct[$1] ?? 0) }
    }

    /// Número de días distintos con un bout en la misma franja horaria (±20 min).
    static func recurringDayCount(for workout: Workout, in all: [Workout]) -> Int {
        let target = minutesSinceMidnight(workout.startTs)
        let window = 20
        let recent = all.filter {
            abs(minutesSinceMidnight($0.startTs) - target) <= window
        }
        let days = Set(recent.map { utcDayKey($0.startTs) })
        return days.count
    }

    // MARK: - Private

    private static func localHour(_ ts: Int) -> Int {
        Calendar.current.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private static func minutesSinceMidnight(_ ts: Int) -> Int {
        let cal = Calendar.current
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        return cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d)
    }

    private static func utcDayKey(_ ts: Int) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private static func localTimeString(_ ts: Int) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
