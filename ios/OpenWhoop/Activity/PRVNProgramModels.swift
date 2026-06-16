import Foundation

// MARK: - PRVN program models (import manual desde PRVN Español / SugarWOD)

enum ProgramBlockKind: String, Codable, CaseIterable {
    case warmup
    case strength
    case metcon
    case accessory
    case other

    var displayName: String {
        switch self {
        case .warmup:    return "Calentamiento"
        case .strength:  return "Fuerza"
        case .metcon:    return "WOD"
        case .accessory: return "Accesorios"
        case .other:     return "Otro"
        }
    }

    var icon: String {
        switch self {
        case .warmup:    return "figure.walk"
        case .strength:  return "dumbbell.fill"
        case .metcon:    return "flame.fill"
        case .accessory: return "plus.circle"
        case .other:     return "text.alignleft"
        }
    }
}

enum PRVNDayType: String, Codable {
    case heavy
    case engine
    case skill
    case mixed
    case rest

    var displayName: String {
        switch self {
        case .heavy:  return "Heavy"
        case .engine: return "Engine"
        case .skill:  return "Skill"
        case .mixed:  return "Mixto"
        case .rest:   return "Descanso"
        }
    }

    /// Recuperación mínima recomendada (%) antes de un día heavy.
    var suggestedRecoveryMin: Int {
        switch self {
        case .heavy:  return 55
        case .engine: return 45
        case .skill:  return 40
        case .mixed:  return 45
        case .rest:   return 0
        }
    }
}

struct ProgramBlock: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: ProgramBlockKind
    let title: String?
    let body: String

    init(id: UUID = UUID(), kind: ProgramBlockKind, title: String? = nil, body: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PRVNDayProgram: Codable, Identifiable, Equatable {
    /// yyyy-MM-dd (calendario local)
    let id: String
    let weekday: Int
    let dayType: PRVNDayType
    let blocks: [ProgramBlock]

    var strengthBlock: ProgramBlock? { blocks.first { $0.kind == .strength } }
    var metconBlock: ProgramBlock? { blocks.first { $0.kind == .metcon } }
    var accessoryBlock: ProgramBlock? { blocks.first { $0.kind == .accessory } }
}

struct PRVNWeekProgram: Codable, Equatable {
    /// Lunes de la semana (yyyy-MM-dd)
    let weekStart: String
    let trackName: String
    let days: [PRVNDayProgram]
    let importedAt: Date

    func program(for date: Date, calendar: Calendar = .current) -> PRVNDayProgram? {
        let key = PRVNProgramStore.dayKey(for: date, calendar: calendar)
        return days.first { $0.id == key }
    }
}
