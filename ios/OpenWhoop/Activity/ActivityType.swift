import SwiftUI

// MARK: - ActivityType
// Catálogo de tipos de actividad para etiquetar entrenos detectados. CrossFit primero
// porque es la actividad principal del usuario. La clasificación real es: etiqueta local
// del usuario  >  `kind` del servidor (autodetectado)  >  sin clasificar.

enum ActivityType: String, CaseIterable, Identifiable, Codable {
    case crossfit
    case running
    case cycling
    case strength
    case hiit
    case walking
    case swimming
    case rowing
    case yoga
    case cardio
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .crossfit:  return "CrossFit"
        case .running:   return "Carrera"
        case .cycling:   return "Ciclismo"
        case .strength:  return "Fuerza"
        case .hiit:      return "HIIT"
        case .walking:   return "Caminata"
        case .swimming:  return "Natación"
        case .rowing:    return "Remo"
        case .yoga:      return "Yoga"
        case .cardio:    return "Cardio"
        case .other:     return "Otra"
        }
    }

    /// SF Symbol para CrossFit (figure.gymnastics desde iOS 16; handstand no existe en el catálogo del sistema).
    var symbol: String {
        switch self {
        case .crossfit:  return "figure.gymnastics"
        case .running:   return "figure.run"
        case .cycling:   return "bicycle"
        case .strength:  return "dumbbell.fill"
        case .hiit:      return "figure.highintensity.intervaltraining"
        case .walking:   return "figure.walk"
        case .swimming:  return "figure.pool.swim"
        case .rowing:    return "figure.rower"
        case .yoga:      return "figure.yoga"
        case .cardio:    return "figure.mixed.cardio"
        case .other:     return "bolt.fill"
        }
    }

    /// Tipos ligeros para actividades que no son entreno (caminata, etc.).
    static let activityOnlyCases: [ActivityType] = [.walking, .yoga, .other]

    /// Mapea el `kind` (texto libre autodetectado en el servidor) a un tipo conocido.
    /// Tolerante: compara en minúsculas y por substring.
    static func from(kind: String?) -> ActivityType? {
        guard let k = kind?.lowercased(), !k.isEmpty else { return nil }
        for t in ActivityType.allCases where t != .other {
            if k.contains(t.rawValue) || k.contains(t.displayName.lowercased()) {
                return t
            }
        }
        if k.contains("run") { return .running }
        if k.contains("bike") || k.contains("cycl") { return .cycling }
        if k.contains("strength") || k.contains("weight") { return .strength }
        if k.contains("swim") { return .swimming }
        if k.contains("walk") { return .walking }
        return nil
    }
}
