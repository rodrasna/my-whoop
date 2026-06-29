import Foundation

// MARK: - Mobility models (local GOWOD-style catalog)

enum MobilityFocusArea: String, Codable, CaseIterable, Identifiable, Hashable {
    case hips, hamstrings, ankles, shoulders, thoracic, wrists, quads, glutes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hips:        return "Caderas"
        case .hamstrings:  return "Isquios"
        case .ankles:      return "Tobillos"
        case .shoulders:   return "Hombros"
        case .thoracic:    return "Torácica"
        case .wrists:      return "Muñecas"
        case .quads:       return "Cuádriceps"
        case .glutes:      return "Glúteos"
        }
    }
}

enum MobilitySessionKind: String, Codable, CaseIterable, Identifiable {
    case daily, preWorkout, postWorkout, preSleep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily:       return "Diaria"
        case .preWorkout:  return "Pre-entreno"
        case .postWorkout: return "Post-entreno"
        case .preSleep:    return "Noche"
        }
    }
}

/// Patrones de movimiento del entreno (PRVN/WOD) para prescribir movilidad específica.
enum MobilityMovementPattern: String, Codable, CaseIterable, Hashable {
    case squat, hinge, overhead, pull, push, locomotion, grip

    var label: String {
        switch self {
        case .squat:      return "sentadilla"
        case .hinge:      return "bisagra de cadera"
        case .overhead:   return "overhead"
        case .pull:       return "tirón"
        case .push:       return "empuje"
        case .locomotion: return "locomoción"
        case .grip:       return "agarre"
        }
    }

    var sortOrder: Int {
        switch self {
        case .squat: return 0
        case .hinge: return 1
        case .overhead: return 2
        case .pull: return 3
        case .push: return 4
        case .locomotion: return 5
        case .grip: return 6
        }
    }
}

enum MobilityMode: String, Codable, CaseIterable {
    case dynamic
    case staticHold
    case activation

    var label: String {
        switch self {
        case .dynamic:     return "dinámico"
        case .staticHold:  return "estático"
        case .activation:  return "activación"
        }
    }
}

enum MobilityPose: String, Codable, CaseIterable {
    case squat, lunge, shoulderCircle, catCow, childPose, wristCircle
    case hipRotation, thoracicRotation, ankleRock, hamstringStretch, standingFold
}

enum MobilityIntensity: String, Codable {
    case gentle, moderate
}

enum MobilitySide: String, Codable, Equatable {
    case left, right

    var label: String {
        switch self {
        case .left:  return "Lado izquierdo"
        case .right: return "Lado derecho"
        }
    }

    var shortLabel: String {
        switch self {
        case .left:  return "Izquierdo"
        case .right: return "Derecho"
        }
    }
}

struct MobilityRoutineStep: Equatable, Identifiable {
    let exercise: MobilityExercise
    let guidedDurationSec: Int
    /// Presente cuando el ejercicio se hace un lado y luego el otro.
    let side: MobilitySide?

    var id: String {
        if let side { return "\(exercise.id)-\(side.rawValue)" }
        return exercise.id
    }

    var displayTitle: String {
        guard let side else { return exercise.name }
        return "\(exercise.name) · \(side.shortLabel)"
    }

    var guidedDurationLabel: String {
        if side != nil {
            return "\(MobilityTiming.durationLabel(seconds: guidedDurationSec)) / lado"
        }
        return MobilityTiming.durationLabel(seconds: guidedDurationSec)
    }
}

struct MobilityExercise: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let focusAreas: [MobilityFocusArea]
    let sessionKinds: [MobilitySessionKind]
    let pose: MobilityPose
    let youtubeURL: String
    /// Nombre de archivo en ExerciseImages/ (sin extensión) o asset catalog.
    let imageAsset: String?
    /// URL remota opcional si no hay imagen local.
    let imageURL: String?
    let durationSec: Int
    let intensity: MobilityIntensity
    let movementPatterns: [MobilityMovementPattern]
    let mobilityMode: MobilityMode
    let maxHoldSec: Int?
    /// Si true, el temporizador guiado corre 1 min por lado (izquierdo y derecho).
    let bilateral: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, name, description, pose, intensity, bilateral
        case focusAreas = "focus_areas"
        case sessionKinds = "session_kinds"
        case youtubeURL = "youtube_url"
        case imageAsset = "image_asset"
        case imageURL = "image_url"
        case durationSec = "duration_sec"
        case movementPatterns = "movement_patterns"
        case mobilityMode = "mobility_mode"
        case maxHoldSec = "max_hold_sec"
    }

    /// Ejercicios que se hacen por lado (cada lado con su propio minuto).
    var isBilateral: Bool {
        if let bilateral { return bilateral }
        if Self.implicitBilateralIDs.contains(id) { return true }
        return Self.descriptionImpliesBilateral(description)
    }

    private static let implicitBilateralIDs: Set<String> = [
        "couch-stretch",
        "ankle-rocks",
        "thread-needle",
        "hip-flexor-lunge",
        "thoracic-rotation-quad",
        "standing-hamstring",
        "doorway-pec-stretch",
        "forearm-extensor-stretch",
    ]

    private static func descriptionImpliesBilateral(_ description: String) -> Bool {
        let d = description.lowercased()
        return d.contains("cambia de lado")
            || d.contains("cambia de pierna")
            || d.contains("alterna lados")
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        focusAreas = try c.decode([MobilityFocusArea].self, forKey: .focusAreas)
        sessionKinds = try c.decode([MobilitySessionKind].self, forKey: .sessionKinds)
        pose = try c.decode(MobilityPose.self, forKey: .pose)
        youtubeURL = try c.decode(String.self, forKey: .youtubeURL)
        imageAsset = try c.decodeIfPresent(String.self, forKey: .imageAsset)
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        durationSec = try c.decode(Int.self, forKey: .durationSec)
        intensity = try c.decode(MobilityIntensity.self, forKey: .intensity)
        movementPatterns = try c.decodeIfPresent([MobilityMovementPattern].self, forKey: .movementPatterns) ?? []
        mobilityMode = try c.decodeIfPresent(MobilityMode.self, forKey: .mobilityMode) ?? .dynamic
        maxHoldSec = try c.decodeIfPresent(Int.self, forKey: .maxHoldSec)
        bilateral = try c.decodeIfPresent(Bool.self, forKey: .bilateral)
    }

    init(
        id: String,
        name: String,
        description: String,
        focusAreas: [MobilityFocusArea],
        sessionKinds: [MobilitySessionKind],
        pose: MobilityPose,
        youtubeURL: String,
        imageAsset: String? = nil,
        imageURL: String? = nil,
        durationSec: Int,
        intensity: MobilityIntensity,
        movementPatterns: [MobilityMovementPattern] = [],
        mobilityMode: MobilityMode = .dynamic,
        maxHoldSec: Int? = nil,
        bilateral: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.focusAreas = focusAreas
        self.sessionKinds = sessionKinds
        self.pose = pose
        self.youtubeURL = youtubeURL
        self.imageAsset = imageAsset
        self.imageURL = imageURL
        self.durationSec = durationSec
        self.intensity = intensity
        self.movementPatterns = movementPatterns
        self.mobilityMode = mobilityMode
        self.maxHoldSec = maxHoldSec
        self.bilateral = bilateral
    }
}

struct MobilityCatalog: Codable, Equatable {
    let exercises: [MobilityExercise]
}

struct MobilityRoutine: Equatable {
    let sessionKind: MobilitySessionKind
    let steps: [MobilityRoutineStep]
    let estimatedMinutes: Int
    let rationale: String
    /// Zonas y patrones que guían esta rutina (p. ej. «Tobillos · sentadilla»).
    let focusSummary: String

    var exercises: [MobilityExercise] { steps.map(\.exercise) }

    var totalDurationSec: Int { steps.reduce(0) { $0 + $1.guidedDurationSec } }
}
