import Foundation

// MARK: - MobilityTiming
// Duración guiada por tipo de sesión y modo de ejercicio (estático vs dinámico).

enum MobilityTiming {

    struct SessionTarget: Equatable {
        let minSec: Int
        let maxSec: Int

        var midpointMinutes: Int {
            max(1, (minSec + maxSec) / 2 / 60)
        }
    }

    /// Ventana objetivo de la sesión guiada.
    static func sessionTarget(
        kind: MobilitySessionKind,
        recoveryPercent: Int? = nil
    ) -> SessionTarget {
        let low = (recoveryPercent ?? 100) < 34
        let moderate = (recoveryPercent ?? 100) < 67
        switch kind {
        case .daily:
            if low { return SessionTarget(minSec: 12 * 60, maxSec: 15 * 60) }
            if moderate { return SessionTarget(minSec: 14 * 60, maxSec: 18 * 60) }
            return SessionTarget(minSec: 15 * 60, maxSec: 20 * 60)
        case .preWorkout:
            if low { return SessionTarget(minSec: 8 * 60, maxSec: 10 * 60) }
            return SessionTarget(minSec: 10 * 60, maxSec: 12 * 60)
        case .postWorkout:
            if low { return SessionTarget(minSec: 6 * 60, maxSec: 8 * 60) }
            return SessionTarget(minSec: 8 * 60, maxSec: 12 * 60)
        case .preSleep:
            return SessionTarget(minSec: 12 * 60, maxSec: 15 * 60)
        }
    }

    /// Duración del temporizador por lado en ejercicios bilaterales.
    static let bilateralSideDurationSec = 60

    /// Segundos totales del temporizador para un ejercicio (ambos lados si es bilateral).
    static func guidedDurationSec(
        for exercise: MobilityExercise,
        sessionKind: MobilitySessionKind
    ) -> Int {
        if exercise.isBilateral {
            return bilateralSideDurationSec * 2
        }
        return guidedDurationSecUnilateral(for: exercise, sessionKind: sessionKind)
    }

    /// Segundos del temporizador para un ejercicio unilateral.
    static func guidedDurationSecUnilateral(
        for exercise: MobilityExercise,
        sessionKind: MobilitySessionKind
    ) -> Int {
        switch (sessionKind, exercise.mobilityMode) {
        case (.preSleep, .staticHold):   return 90
        case (.preSleep, .dynamic):      return 45
        case (.preSleep, .activation):   return 30
        case (.daily, .staticHold):      return 90
        case (.daily, .dynamic):         return 60
        case (.daily, .activation):       return 45
        case (.preWorkout, .staticHold): return 40
        case (.preWorkout, .dynamic):     return 45
        case (.preWorkout, .activation): return 40
        case (.postWorkout, .staticHold): return 75
        case (.postWorkout, .dynamic):    return 45
        case (.postWorkout, .activation): return 30
        }
    }

    static func durationLabel(seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 {
            let m = seconds / 60
            return m == 1 ? "1 min" : "\(m) min"
        }
        if seconds >= 60 {
            return "\(seconds / 60) min \(seconds % 60) s"
        }
        return "\(seconds) s"
    }
}
