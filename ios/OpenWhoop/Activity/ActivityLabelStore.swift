import Foundation
import SwiftUI

// MARK: - ActivityLabelStore
// Persistencia local (UserDefaults) de las etiquetas de tipo de actividad que el usuario
// asigna a cada entreno detectado. Keyed por `workout.id` ("deviceId|startTs"). No toca
// el servidor: es una capa de etiquetado del cliente que más adelante puede alimentar un
// clasificador automático a partir del histórico etiquetado.

@MainActor
final class ActivityLabelStore: ObservableObject {

    private static let key = "com.openwhoop.activityLabels.v1"
    private static let samplesKey = "com.openwhoop.activitySamples.v1"
    private static let dismissedKey = "com.openwhoop.dismissedBouts.v1"
    private static let activityOnlyKey = "com.openwhoop.activityOnlyLabels.v1"
    private static let sessionStylesKey = "com.openwhoop.crossfitSessionStyles.v1"

    /// Mínimo de muestras etiquetadas antes de empezar a sugerir (evita sugerir con poca evidencia).
    private static let minSamplesToSuggest = 4
    /// k vecinos y umbral de distancia máxima para aceptar una sugerencia.
    private static let kNeighbors = 3
    private static let maxAcceptDistance = 0.45

    @Published private(set) var labels: [String: ActivityType] = [:]
    /// Bouts que el usuario marcó como actividad cotidiana (no entreno).
    @Published private(set) var dismissed: Set<String> = []
    /// Etiqueta opcional para actividades que no son entreno (caminata, otra…).
    @Published private(set) var activityOnly: [String: ActivityType] = [:]
    /// Dataset de referencia: firma + etiqueta de cada entreno que el usuario ha clasificado.
    @Published private(set) var samples: [String: ActivitySample] = [:]
    /// Subtipo CrossFit (clasificatorio, benchmark…) por entreno.
    @Published private(set) var sessionStyles: [String: CrossFitSessionStyle] = [:]

    init() {
        if let raw = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] {
            labels = raw.compactMapValues { ActivityType(rawValue: $0) }
        }
        if let data = UserDefaults.standard.data(forKey: Self.samplesKey),
           let decoded = try? JSONDecoder().decode([String: ActivitySample].self, from: data) {
            samples = decoded
        }
        if let arr = UserDefaults.standard.array(forKey: Self.dismissedKey) as? [String] {
            dismissed = Set(arr)
        }
        if let raw = UserDefaults.standard.dictionary(forKey: Self.activityOnlyKey) as? [String: String] {
            activityOnly = raw.compactMapValues { ActivityType(rawValue: $0) }
        }
        if let raw = UserDefaults.standard.dictionary(forKey: Self.sessionStylesKey) as? [String: String] {
            sessionStyles = raw.compactMapValues { CrossFitSessionStyle(rawValue: $0) }
        }
    }

    func sessionStyle(for workout: Workout) -> CrossFitSessionStyle? {
        sessionStyles[workout.id]
    }

    func displayTitle(for workout: Workout) -> String? {
        guard let type = effectiveType(for: workout) else { return nil }
        if type == .crossfit, let style = sessionStyles[workout.id], style != .regular {
            return "\(type.displayName) · \(style.displayName)"
        }
        return type.displayName
    }

    /// Etiqueta efectiva: etiqueta manual del usuario, si no la hay deriva del `kind` del servidor.
    func effectiveType(for workout: Workout) -> ActivityType? {
        labels[workout.id] ?? ActivityType.from(kind: workout.kind)
    }

    /// Solo la etiqueta manual (sin fallback al servidor). Útil para distinguir "ya clasificado por mí".
    func manualLabel(for id: String) -> ActivityType? {
        labels[id]
    }

    func isDismissed(_ id: String) -> Bool { dismissed.contains(id) }

    func activityOnlyType(for workout: Workout) -> ActivityType? {
        activityOnly[workout.id]
    }

    func isConfirmed(_ workout: Workout) -> Bool {
        manualLabel(for: workout.id) != nil
    }

    /// Actividad cotidiana: visible en Actividad pero no cuenta como entreno.
    func markAsActivityOnly(_ workout: Workout, type: ActivityType? = nil) {
        dismissed.insert(workout.id)
        labels.removeValue(forKey: workout.id)
        samples.removeValue(forKey: workout.id)
        if let type { activityOnly[workout.id] = type }
        else { activityOnly.removeValue(forKey: workout.id) }
        persist()
    }

    /// El usuario indica que este bout NO fue un entreno (p. ej. rutina matutina).
    func dismissAsNotWorkout(_ workout: Workout) {
        markAsActivityOnly(workout, type: nil)
    }

    func restoreAsWorkoutCandidate(_ workoutId: String) {
        dismissed.remove(workoutId)
        activityOnly.removeValue(forKey: workoutId)
        persist()
    }

    func restoreDismissed(_ workoutId: String) {
        restoreAsWorkoutCandidate(workoutId)
    }

    /// Cuántas sesiones de referencia hay de un tipo concreto.
    func sampleCount(of type: ActivityType) -> Int {
        samples.values.filter { $0.label == type.rawValue }.count
    }

    /// Asigna una etiqueta capturando además la firma del entreno como muestra de referencia.
    func set(_ type: ActivityType?, for workout: Workout) {
        if let type {
            labels[workout.id] = type
            samples[workout.id] = ActivitySample.make(from: workout, label: type)
            dismissed.remove(workout.id)
            activityOnly.removeValue(forKey: workout.id)
            if type != .crossfit { sessionStyles.removeValue(forKey: workout.id) }
        } else {
            labels.removeValue(forKey: workout.id)
            samples.removeValue(forKey: workout.id)
            sessionStyles.removeValue(forKey: workout.id)
        }
        persist()
    }

    func setSessionStyle(_ style: CrossFitSessionStyle?, for workout: Workout) {
        if let style, style != .regular {
            sessionStyles[workout.id] = style
        } else {
            sessionStyles.removeValue(forKey: workout.id)
        }
        persist()
    }

    /// Quita la etiqueta por id (sin firma; usado cuando no tenemos el Workout completo).
    func set(_ type: ActivityType?, for id: String) {
        if let type {
            labels[id] = type
        } else {
            labels.removeValue(forKey: id)
            samples.removeValue(forKey: id)
        }
        persist()
    }

    /// Sugerencia automática (k-NN) para un entreno sin clasificar, a partir del histórico
    /// etiquetado por el usuario. Devuelve nil si no hay evidencia suficiente o el vecino más
    /// cercano queda demasiado lejos. Solo sugiere tipos que el usuario ya haya usado.
    func suggestion(for workout: Workout) -> ActivityType? {
        guard samples.count >= Self.minSamplesToSuggest else { return nil }
        let target = ActivitySample.features(of: workout)
        let ranked = samples.values
            .map { (type: $0.type, dist: ActivitySample.distance(target, $0.features)) }
            .compactMap { item -> (ActivityType, Double)? in
                guard let t = item.type else { return nil }
                return (t, item.dist)
            }
            .sorted { $0.1 < $1.1 }
        let neighbors = Array(ranked.prefix(Self.kNeighbors))
        guard let nearest = neighbors.first, nearest.1 <= Self.maxAcceptDistance else { return nil }
        // Voto mayoritario entre los k más cercanos (que estén dentro del umbral).
        var votes: [ActivityType: Int] = [:]
        for (t, d) in neighbors where d <= Self.maxAcceptDistance { votes[t, default: 0] += 1 }
        return votes.max { $0.value < $1.value }?.key ?? nearest.0
    }

    /// Inyecta muestras de referencia sin persistir (solo para vista previa/verificación en simulador).
    func seedSamples(_ injected: [ActivitySample]) {
        for s in injected { samples[s.workoutId] = s }
    }

    private func persist() {
        let raw = labels.mapValues { $0.rawValue }
        UserDefaults.standard.set(raw, forKey: Self.key)
        UserDefaults.standard.set(Array(dismissed), forKey: Self.dismissedKey)
        let activityRaw = activityOnly.mapValues { $0.rawValue }
        UserDefaults.standard.set(activityRaw, forKey: Self.activityOnlyKey)
        if let data = try? JSONEncoder().encode(samples) {
            UserDefaults.standard.set(data, forKey: Self.samplesKey)
        }
        let stylesRaw = sessionStyles.mapValues { $0.rawValue }
        UserDefaults.standard.set(stylesRaw, forKey: Self.sessionStylesKey)
    }
}
