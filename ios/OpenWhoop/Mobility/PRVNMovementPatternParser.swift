import Foundation

// MARK: - PRVNMovementPatternParser
// Patrones de movimiento desde bloques PRVN para prescribir movilidad pre-entreno.
// Puntuación por bloque (WOD > fuerza > accesorio) y keywords con menos falsos positivos.

enum PRVNMovementPatternParser {

    struct ScanOptions: Equatable {
        /// Si no está vacío, solo se analizan estos tipos de bloque.
        var blocksDone: [ProgramBlockKind] = []
        /// Puntuación mínima acumulada para incluir un patrón.
        var minimumScore: Int = 2
        /// Máximo de patrones devueltos (los de mayor puntuación).
        var maxPatterns: Int = 6
    }

    private struct KeywordRule {
        let pattern: MobilityMovementPattern
        let term: String
        let weight: Int
        let wordBoundary: Bool
    }

    // MARK: - Public API

    static func patterns(
        from program: PRVNDayProgram?,
        blocksDone: [ProgramBlockKind] = [],
        options: ScanOptions = ScanOptions()
    ) -> Set<MobilityMovementPattern> {
        Set(rankedPatterns(from: program, blocksDone: blocksDone, options: options))
    }

    static func rankedPatterns(
        from program: PRVNDayProgram?,
        blocksDone: [ProgramBlockKind] = [],
        options: ScanOptions = ScanOptions()
    ) -> [MobilityMovementPattern] {
        guard let program else { return [] }
        var opts = options
        if !blocksDone.isEmpty {
            opts.blocksDone = blocksDone
        }
        let scores = scoresForProgram(program, options: opts)
        return selectPatterns(from: scores, options: opts)
    }

    /// Análisis de texto libre (tests o bloque suelto).
    static func patterns(in text: String) -> Set<MobilityMovementPattern> {
        let scores = scoresInText(text, blockWeight: 1)
        return Set(selectPatterns(from: scores, options: ScanOptions(minimumScore: 1)))
    }

    static func focusAreas(for patterns: Set<MobilityMovementPattern>) -> Set<MobilityFocusArea> {
        var areas = Set<MobilityFocusArea>()
        for pattern in patterns {
            areas.formUnion(focusAreas(for: pattern))
        }
        return areas
    }

    static func focusAreas(for pattern: MobilityMovementPattern) -> Set<MobilityFocusArea> {
        switch pattern {
        case .squat:      return [.ankles, .hips, .thoracic]
        case .hinge:      return [.hips, .hamstrings, .thoracic]
        case .overhead:   return [.shoulders, .thoracic, .wrists, .ankles]
        case .pull:       return [.shoulders, .thoracic, .wrists]
        case .push:       return [.shoulders, .thoracic, .wrists]
        case .locomotion: return [.ankles, .hips, .quads, .hamstrings]
        case .grip:       return [.wrists, .shoulders]
        }
    }

    static func patternLabels(_ patterns: Set<MobilityMovementPattern>) -> String {
        patterns
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.label)
            .joined(separator: ", ")
    }

    // MARK: - Program scan

    private static func scoresForProgram(
        _ program: PRVNDayProgram,
        options: ScanOptions
    ) -> [MobilityMovementPattern: Int] {
        let allowedKinds = Set(options.blocksDone)
        var total: [MobilityMovementPattern: Int] = [:]

        for block in program.blocks {
            guard block.kind != .warmup else { continue }
            if !allowedKinds.isEmpty, !allowedKinds.contains(block.kind) { continue }

            let weight = blockWeight(block.kind)
            let text = blockScanText(block)
            let blockScores = scoresInText(text, blockWeight: weight)
            for (pattern, score) in blockScores {
                total[pattern, default: 0] += score
            }
        }
        return total
    }

    private static func blockScanText(_ block: ProgramBlock) -> String {
        var parts: [String] = []
        if let title = block.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            parts.append(title)
        }
        parts.append(block.body)
        let summary = PRVNBlockSummary.oneLine(for: block)
        if !summary.isEmpty {
            parts.append(summary)
        }
        return parts.joined(separator: "\n")
    }

    private static func blockWeight(_ kind: ProgramBlockKind) -> Int {
        switch kind {
        case .metcon:    return 4
        case .strength:  return 3
        case .accessory: return 1
        case .other:     return 1
        case .warmup:    return 0
        }
    }

    private static func scoresInText(
        _ text: String,
        blockWeight: Int
    ) -> [MobilityMovementPattern: Int] {
        let normalized = normalize(text)
        var scores: [MobilityMovementPattern: Int] = [:]

        for rule in keywordRules {
            if matches(term: rule.term, in: normalized, wordBoundary: rule.wordBoundary) {
                scores[rule.pattern, default: 0] += rule.weight * blockWeight
            }
        }
        return scores
    }

    private static func selectPatterns(
        from scores: [MobilityMovementPattern: Int],
        options: ScanOptions
    ) -> [MobilityMovementPattern] {
        scores
            .filter { $0.value >= options.minimumScore }
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return a.key.sortOrder < b.key.sortOrder
            }
            .prefix(options.maxPatterns)
            .map(\.key)
    }

    // MARK: - Keyword matching

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
    }

    private static func matches(term: String, in normalized: String, wordBoundary: Bool) -> Bool {
        guard !term.isEmpty else { return false }
        if wordBoundary {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            let pattern = "(?<![a-z0-9])\(escaped)(?![a-z0-9])"
            return normalized.range(of: pattern, options: .regularExpression) != nil
        }
        return normalized.contains(term)
    }

    /// Reglas ordenadas: frases largas primero (más específicas).
    private static let keywordRules: [KeywordRule] = {
        let raw: [KeywordRule] = [
            // Squat
            .init(pattern: .squat, term: "back squat", weight: 4, wordBoundary: false),
            .init(pattern: .squat, term: "front squat", weight: 4, wordBoundary: false),
            .init(pattern: .squat, term: "overhead squat", weight: 4, wordBoundary: false),
            .init(pattern: .squat, term: "goblet squat", weight: 3, wordBoundary: false),
            .init(pattern: .squat, term: "air squat", weight: 3, wordBoundary: false),
            .init(pattern: .squat, term: "squat clean", weight: 3, wordBoundary: false),
            .init(pattern: .squat, term: "squat snatch", weight: 3, wordBoundary: false),
            .init(pattern: .squat, term: "wall ball", weight: 3, wordBoundary: false),
            .init(pattern: .squat, term: "wall balls", weight: 3, wordBoundary: false),
            .init(pattern: .squat, term: "wall-ball", weight: 3, wordBoundary: false),
            .init(pattern: .squat, term: "sentadilla", weight: 3, wordBoundary: false),
            .init(pattern: .squat, term: "thruster", weight: 3, wordBoundary: true),
            .init(pattern: .squat, term: "squat", weight: 2, wordBoundary: true),
            .init(pattern: .squat, term: "squats", weight: 2, wordBoundary: true),

            // Hinge
            .init(pattern: .hinge, term: "peso muerto", weight: 4, wordBoundary: false),
            .init(pattern: .hinge, term: "deadlift", weight: 4, wordBoundary: true),
            .init(pattern: .hinge, term: "romanian", weight: 3, wordBoundary: true),
            .init(pattern: .hinge, term: "good morning", weight: 3, wordBoundary: false),
            .init(pattern: .hinge, term: "kettlebell swing", weight: 4, wordBoundary: false),
            .init(pattern: .hinge, term: "kb swing", weight: 3, wordBoundary: false),
            .init(pattern: .hinge, term: "clean pull", weight: 3, wordBoundary: false),
            .init(pattern: .hinge, term: "snatch pull", weight: 3, wordBoundary: false),
            .init(pattern: .hinge, term: "hip hinge", weight: 3, wordBoundary: false),
            .init(pattern: .hinge, term: "rdl", weight: 3, wordBoundary: true),
            .init(pattern: .hinge, term: "hinge", weight: 2, wordBoundary: true),

            // Overhead
            .init(pattern: .overhead, term: "muscle-up", weight: 4, wordBoundary: false),
            .init(pattern: .overhead, term: "muscle up", weight: 4, wordBoundary: false),
            .init(pattern: .overhead, term: "handstand push", weight: 4, wordBoundary: false),
            .init(pattern: .overhead, term: "hspu", weight: 4, wordBoundary: true),
            .init(pattern: .overhead, term: "push jerk", weight: 3, wordBoundary: false),
            .init(pattern: .overhead, term: "split jerk", weight: 3, wordBoundary: false),
            .init(pattern: .overhead, term: "power snatch", weight: 4, wordBoundary: false),
            .init(pattern: .overhead, term: "squat snatch", weight: 4, wordBoundary: false),
            .init(pattern: .overhead, term: "snatch", weight: 3, wordBoundary: true),
            .init(pattern: .overhead, term: "arranque", weight: 3, wordBoundary: true),
            .init(pattern: .overhead, term: "envion", weight: 3, wordBoundary: true),
            .init(pattern: .overhead, term: "overhead", weight: 2, wordBoundary: true),
            .init(pattern: .overhead, term: "strict press", weight: 3, wordBoundary: false),
            .init(pattern: .overhead, term: "shoulder press", weight: 3, wordBoundary: false),
            .init(pattern: .overhead, term: "press de hombro", weight: 3, wordBoundary: false),
            .init(pattern: .overhead, term: "push press", weight: 3, wordBoundary: false),
            .init(pattern: .overhead, term: "handstand", weight: 3, wordBoundary: true),
            .init(pattern: .overhead, term: "jerk", weight: 2, wordBoundary: true),

            // Pull
            .init(pattern: .pull, term: "pull-up", weight: 4, wordBoundary: false),
            .init(pattern: .pull, term: "pull-ups", weight: 4, wordBoundary: false),
            .init(pattern: .pull, term: "pull up", weight: 4, wordBoundary: false),
            .init(pattern: .pull, term: "chin-up", weight: 4, wordBoundary: false),
            .init(pattern: .pull, term: "chest to bar", weight: 4, wordBoundary: false),
            .init(pattern: .pull, term: "toes to bar", weight: 3, wordBoundary: false),
            .init(pattern: .pull, term: "rope climb", weight: 3, wordBoundary: false),
            .init(pattern: .pull, term: "dominada", weight: 3, wordBoundary: true),
            .init(pattern: .pull, term: "pullup", weight: 3, wordBoundary: true),
            .init(pattern: .pull, term: "remo en anillas", weight: 3, wordBoundary: false),

            // Push
            .init(pattern: .push, term: "push-up", weight: 4, wordBoundary: false),
            .init(pattern: .push, term: "push-ups", weight: 4, wordBoundary: false),
            .init(pattern: .push, term: "push up", weight: 4, wordBoundary: false),
            .init(pattern: .push, term: "bench press", weight: 4, wordBoundary: false),
            .init(pattern: .push, term: "press banca", weight: 4, wordBoundary: false),
            .init(pattern: .push, term: "ring dip", weight: 3, wordBoundary: false),
            .init(pattern: .push, term: "flexion", weight: 2, wordBoundary: true),
            .init(pattern: .push, term: "fondo", weight: 2, wordBoundary: true),
            .init(pattern: .push, term: "dip", weight: 2, wordBoundary: true),

            // Locomotion
            .init(pattern: .locomotion, term: "double under", weight: 3, wordBoundary: false),
            .init(pattern: .locomotion, term: "box jump", weight: 3, wordBoundary: false),
            .init(pattern: .locomotion, term: "ski erg", weight: 3, wordBoundary: false),
            .init(pattern: .locomotion, term: "assault bike", weight: 3, wordBoundary: false),
            .init(pattern: .locomotion, term: "saltar la cuerda", weight: 3, wordBoundary: false),
            .init(pattern: .locomotion, term: "burpee", weight: 3, wordBoundary: true),
            .init(pattern: .locomotion, term: "burpees", weight: 3, wordBoundary: true),
            .init(pattern: .locomotion, term: "running", weight: 2, wordBoundary: true),
            .init(pattern: .locomotion, term: "correr", weight: 2, wordBoundary: true),
            .init(pattern: .locomotion, term: "carrera", weight: 2, wordBoundary: true),
            .init(pattern: .locomotion, term: "rowing", weight: 2, wordBoundary: true),
            .init(pattern: .locomotion, term: "remo", weight: 2, wordBoundary: true),
            .init(pattern: .locomotion, term: "row", weight: 2, wordBoundary: true),
            .init(pattern: .locomotion, term: " run", weight: 2, wordBoundary: false),
            .init(pattern: .locomotion, term: " row", weight: 2, wordBoundary: false),
            .init(pattern: .locomotion, term: " bike", weight: 2, wordBoundary: false),
            .init(pattern: .locomotion, term: "bici", weight: 2, wordBoundary: true),

            // Grip
            .init(pattern: .grip, term: "farmer carry", weight: 4, wordBoundary: false),
            .init(pattern: .grip, term: "farmer walk", weight: 4, wordBoundary: false),
            .init(pattern: .grip, term: "hang clean", weight: 3, wordBoundary: false),
            .init(pattern: .grip, term: "hang snatch", weight: 3, wordBoundary: false),
            .init(pattern: .grip, term: "kipping", weight: 2, wordBoundary: true),
            .init(pattern: .grip, term: "farmer", weight: 2, wordBoundary: true),
            .init(pattern: .grip, term: "carry", weight: 2, wordBoundary: true),
            .init(pattern: .grip, term: "arrastre", weight: 2, wordBoundary: true),
        ]
        return raw.sorted { $0.term.count > $1.term.count }
    }()
}
