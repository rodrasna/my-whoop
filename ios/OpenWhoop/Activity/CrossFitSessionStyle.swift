import Foundation

// MARK: - CrossFitSessionStyle
// Subtipo de sesión CrossFit (clasificatorio, benchmark, etc.) guardado por entreno detectado.

enum CrossFitSessionStyle: String, Codable, CaseIterable, Identifiable {
    case regular
    case qualifier
    case benchmark
    case hero
    case skill
    case partner

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regular:   return "Sesión normal"
        case .qualifier: return "Clasificatorio"
        case .benchmark: return "Benchmark"
        case .hero:      return "Hero WOD"
        case .skill:     return "Skill"
        case .partner:   return "Partner"
        }
    }

    var icon: String {
        switch self {
        case .regular:   return "figure.gymnastics"
        case .qualifier: return "trophy.fill"
        case .benchmark: return "chart.bar.fill"
        case .hero:      return "flame.fill"
        case .skill:     return "hand.raised.fill"
        case .partner:   return "person.2.fill"
        }
    }
}
