import Foundation

// MARK: - MobilityRoutineBuilder

enum MobilityRoutineBuilder {

    struct Context {
        var dayKey: String
        var sessionKind: MobilitySessionKind
        var focusAreas: Set<MobilityFocusArea>
        var prvnDayType: PRVNDayType?
        var movementPatterns: Set<MobilityMovementPattern> = []
        var recoveryPercent: Int? = nil
        var assessmentWeakAreas: Set<MobilityFocusArea> = []
    }

    static func build(
        catalog: [MobilityExercise],
        context: Context
    ) -> MobilityRoutine {
        switch context.sessionKind {
        case .daily:
            return buildDaily(catalog: catalog, context: context)
        case .preWorkout:
            return buildPreWorkout(catalog: catalog, context: context)
        case .postWorkout:
            return buildPostWorkout(catalog: catalog, context: context)
        case .preSleep:
            return buildPreSleep(catalog: catalog, context: context)
        }
    }

    // MARK: - Daily (15–20 min estiramientos)

    private static func buildDaily(
        catalog: [MobilityExercise],
        context: Context
    ) -> MobilityRoutine {
        let pool = catalog.filter { $0.sessionKinds.contains(.daily) }
        let dailyFocus = context.focusAreas.union(context.assessmentWeakAreas)
        let patterns = context.movementPatterns

        var picked: [MobilityExercise] = []

        if !context.assessmentWeakAreas.isEmpty {
            picked.append(contentsOf: pickScored(
                pool: pool.filter { ex in !picked.contains(where: { $0.id == ex.id }) },
                count: 3,
                seed: context.dayKey + "-daily-weak",
                score: { scoreDaily($0, focus: context.assessmentWeakAreas, patterns: patterns, boostWeak: true) }
            ))
        }

        picked.append(contentsOf: pickScored(
            pool: pool.filter { ex in !picked.contains(where: { $0.id == ex.id }) },
            count: 2,
            seed: context.dayKey + "-daily-focus",
            score: { scoreDaily($0, focus: context.focusAreas, patterns: patterns, boostWeak: false) }
        ))

        if !patterns.isEmpty {
            for pattern in patterns.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let match = pickScored(
                    pool: pool.filter { ex in
                        !picked.contains(where: { $0.id == ex.id })
                            && ex.movementPatterns.contains(pattern)
                    },
                    count: 1,
                    seed: context.dayKey + "-daily-pat-\(pattern.rawValue)",
                    score: { scoreDaily($0, focus: dailyFocus, patterns: patterns, boostWeak: false) }
                )
                picked.append(contentsOf: match)
            }
        }

        let target = MobilityTiming.sessionTarget(kind: .daily, recoveryPercent: context.recoveryPercent)
        picked = fillToDuration(
            picked: picked,
            pool: pool,
            target: target,
            sessionKind: .daily,
            seed: context.dayKey + "-daily-fill",
            score: { scoreDaily($0, focus: dailyFocus, patterns: patterns, boostWeak: false) }
        )

        var rationale = "Sesión de estiramientos ~\(target.midpointMinutes) min — priorizamos \(focusLabel(dailyFocus))."
        if !context.assessmentWeakAreas.isEmpty {
            rationale += " Refuerzo en zonas débiles del test."
        }
        if !patterns.isEmpty {
            rationale += " Alineada con \(PRVNMovementPatternParser.patternLabels(patterns))."
        }
        if isRecoveryLimited(context.recoveryPercent) {
            rationale += " Recuperación baja: sesión algo más corta."
        }

        return makeRoutine(
            kind: .daily,
            exercises: picked,
            rationale: rationale,
            focusAreas: dailyFocus,
            patterns: patterns
        )
    }

    // MARK: - Pre-workout (10–12 min, específica al WOD)

    private static func buildPreWorkout(
        catalog: [MobilityExercise],
        context: Context
    ) -> MobilityRoutine {
        let dayType = context.prvnDayType ?? .mixed
        if dayType == .rest {
            return buildDaily(catalog: catalog, context: Context(
                dayKey: context.dayKey,
                sessionKind: .daily,
                focusAreas: context.focusAreas,
                prvnDayType: dayType,
                movementPatterns: context.movementPatterns,
                recoveryPercent: context.recoveryPercent,
                assessmentWeakAreas: context.assessmentWeakAreas
            ))
        }

        let patterns = context.movementPatterns
        let priority: Set<MobilityFocusArea> = patterns.isEmpty
            ? priorityAreas(for: dayType)
            : PRVNMovementPatternParser.focusAreas(for: patterns)

        let pool = filteredPreWorkoutPool(catalog: catalog, recoveryPercent: context.recoveryPercent)
        var picked: [MobilityExercise] = []

        if !patterns.isEmpty {
            for pattern in patterns.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let patternAreas = PRVNMovementPatternParser.focusAreas(for: pattern)
                let match = pickScored(
                    pool: pool.filter { ex in
                        !picked.contains(where: { $0.id == ex.id })
                            && ex.movementPatterns.contains(pattern)
                    },
                    count: 1,
                    seed: context.dayKey + "-pre-pat-\(pattern.rawValue)",
                    score: { scorePreWorkout($0, patterns: patterns, priority: patternAreas, focus: context.focusAreas, recovery: context.recoveryPercent) }
                )
                picked.append(contentsOf: match)
            }
        }

        picked.append(contentsOf: pickScored(
            pool: pool.filter { ex in !picked.contains(where: { $0.id == ex.id }) },
            count: 2,
            seed: context.dayKey + "-pre-priority",
            score: { scorePreWorkout($0, patterns: patterns, priority: priority, focus: context.focusAreas, recovery: context.recoveryPercent) }
        ))

        let target = MobilityTiming.sessionTarget(kind: .preWorkout, recoveryPercent: context.recoveryPercent)
        picked = fillToDuration(
            picked: picked,
            pool: pool,
            target: target,
            sessionKind: .preWorkout,
            seed: context.dayKey + "-pre-fill",
            score: { scorePreWorkout($0, patterns: patterns, priority: priority, focus: context.focusAreas, recovery: context.recoveryPercent) }
        )

        let rationale = rationaleForPreWorkout(
            dayType: dayType,
            patterns: patterns,
            priority: priority,
            recoveryPercent: context.recoveryPercent,
            targetMinutes: target.midpointMinutes
        )
        return makeRoutine(
            kind: .preWorkout,
            exercises: picked,
            rationale: rationale,
            focusAreas: priority.union(context.focusAreas),
            patterns: patterns
        )
    }

    // MARK: - Post-workout (8–12 min descompresión)

    private static func buildPostWorkout(
        catalog: [MobilityExercise],
        context: Context
    ) -> MobilityRoutine {
        let pool = catalog.filter { ex in
            (ex.sessionKinds.contains(.daily) || ex.sessionKinds.contains(.preSleep))
                && (ex.intensity == .gentle || ex.mobilityMode == .staticHold)
        }
        let patterns = context.movementPatterns
        let focus = context.focusAreas.union(PRVNMovementPatternParser.focusAreas(for: patterns))

        var picked: [MobilityExercise] = []

        if !patterns.isEmpty {
            for pattern in patterns.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let match = pickScored(
                    pool: pool.filter { ex in
                        !picked.contains(where: { $0.id == ex.id })
                            && ex.movementPatterns.contains(pattern)
                    },
                    count: 1,
                    seed: context.dayKey + "-post-pat-\(pattern.rawValue)",
                    score: { scorePostWorkout($0, patterns: patterns, focus: focus) }
                )
                picked.append(contentsOf: match)
            }
        }

        picked.append(contentsOf: pickScored(
            pool: pool.filter { ex in !picked.contains(where: { $0.id == ex.id }) },
            count: 2,
            seed: context.dayKey + "-post-focus",
            score: { scorePostWorkout($0, patterns: patterns, focus: focus) }
        ))

        let target = MobilityTiming.sessionTarget(kind: .postWorkout, recoveryPercent: context.recoveryPercent)
        picked = fillToDuration(
            picked: picked,
            pool: pool,
            target: target,
            sessionKind: .postWorkout,
            seed: context.dayKey + "-post-fill",
            score: { scorePostWorkout($0, patterns: patterns, focus: focus) }
        )

        let patternLabel = patterns.isEmpty
            ? nil
            : PRVNMovementPatternParser.patternLabels(patterns)
        var rationale = "~\(target.midpointMinutes) min de descompresión tras el entreno."
        if let patternLabel {
            rationale += " Zonas trabajadas: \(patternLabel)."
        }

        return makeRoutine(
            kind: .postWorkout,
            exercises: picked,
            rationale: rationale,
            focusAreas: focus,
            patterns: patterns
        )
    }

    // MARK: - Pre-sleep (12–15 min suave)

    private static func buildPreSleep(
        catalog: [MobilityExercise],
        context: Context
    ) -> MobilityRoutine {
        let gentlePool = catalog.filter {
            $0.sessionKinds.contains(.preSleep) && $0.intensity == .gentle
        }
        let priority: Set<MobilityFocusArea> = [.hamstrings, .thoracic, .hips]

        var picked = pickFromFocus(pool: gentlePool, focus: priority, count: 4, seed: context.dayKey + "-sleep-priority")
        picked.append(contentsOf: pickFromFocus(
            pool: gentlePool.filter { !picked.contains($0) },
            focus: context.focusAreas,
            count: 2,
            seed: context.dayKey + "-sleep-user"
        ))

        let target = MobilityTiming.sessionTarget(kind: .preSleep, recoveryPercent: context.recoveryPercent)
        picked = fillToDuration(
            picked: picked,
            pool: gentlePool,
            target: target,
            sessionKind: .preSleep,
            seed: context.dayKey + "-sleep-fill",
            score: { ex in ex.focusAreas.filter { priority.contains($0) }.count }
        )

        return makeRoutine(
            kind: .preSleep,
            exercises: picked,
            rationale: "Estiramientos suaves ~\(target.midpointMinutes) min — isquios, torácica y caderas para dormir.",
            focusAreas: priority.union(context.focusAreas),
            patterns: []
        )
    }

    // MARK: - Duration fill

    private static func fillToDuration(
        picked: [MobilityExercise],
        pool: [MobilityExercise],
        target: MobilityTiming.SessionTarget,
        sessionKind: MobilitySessionKind,
        seed: String,
        score: (MobilityExercise) -> Int
    ) -> [MobilityExercise] {
        var result = picked
        let maxSteps = 20

        func totalSec(_ list: [MobilityExercise]) -> Int {
            list.reduce(0) { $0 + MobilityTiming.guidedDurationSec(for: $1, sessionKind: sessionKind) }
        }

        var uniqueRemaining = pool.filter { ex in !result.contains(where: { $0.id == ex.id }) }
        var fillIdx = 0

        while totalSec(result) < target.minSec, result.count < maxSteps, !uniqueRemaining.isEmpty {
            let next = pickScored(
                pool: uniqueRemaining,
                count: 1,
                seed: seed + "-u\(fillIdx)",
                score: score
            )
            guard let ex = next.first else { break }
            let add = MobilityTiming.guidedDurationSec(for: ex, sessionKind: sessionKind)
            let projected = totalSec(result) + add
            if projected > target.maxSec {
                if totalSec(result) >= target.minSec { break }
                uniqueRemaining.removeAll { $0.id == ex.id }
                fillIdx += 1
                continue
            }
            result.append(ex)
            uniqueRemaining.removeAll { $0.id == ex.id }
            fillIdx += 1
        }

        // Segunda vuelta: repetir estiramientos clave hasta cubrir el tiempo objetivo.
        let baseCount = result.count
        var round = 0
        while totalSec(result) < target.minSec, result.count < maxSteps, baseCount > 0 {
            let ex = result[round % baseCount]
            let add = MobilityTiming.guidedDurationSec(for: ex, sessionKind: sessionKind)
            if totalSec(result) + add > target.maxSec { break }
            result.append(ex)
            round += 1
        }

        while totalSec(result) > target.maxSec, result.count > 3 {
            result.removeLast()
        }

        return result
    }

    // MARK: - Scoring

    private static func scorePreWorkout(
        _ exercise: MobilityExercise,
        patterns: Set<MobilityMovementPattern>,
        priority: Set<MobilityFocusArea>,
        focus: Set<MobilityFocusArea>,
        recovery: Int?
    ) -> Int {
        var score = 0
        if !patterns.isEmpty {
            score += 4 * exercise.movementPatterns.filter { patterns.contains($0) }.count
        }
        score += 2 * exercise.focusAreas.filter { priority.contains($0) }.count
        score += 2 * exercise.focusAreas.filter { focus.contains($0) }.count

        switch exercise.mobilityMode {
        case .activation: score += 2
        case .dynamic:    score += 1
        case .staticHold: score += 0
        }

        if let recovery, recovery < 67, exercise.mobilityMode == .staticHold {
            let hold = exercise.maxHoldSec ?? exercise.durationSec
            if hold > 60 { score -= 4 }
        }
        if let recovery, recovery < 34, exercise.intensity == .moderate {
            score -= 2
        }
        return score
    }

    private static func scorePostWorkout(
        _ exercise: MobilityExercise,
        patterns: Set<MobilityMovementPattern>,
        focus: Set<MobilityFocusArea>
    ) -> Int {
        var score = 0
        if !patterns.isEmpty {
            score += 4 * exercise.movementPatterns.filter { patterns.contains($0) }.count
        }
        score += 2 * exercise.focusAreas.filter { focus.contains($0) }.count
        switch exercise.mobilityMode {
        case .staticHold: score += 3
        case .dynamic:    score += 1
        case .activation: score -= 1
        }
        if exercise.intensity == .gentle { score += 2 }
        return score
    }

    private static func scoreDaily(
        _ exercise: MobilityExercise,
        focus: Set<MobilityFocusArea>,
        patterns: Set<MobilityMovementPattern>,
        boostWeak: Bool
    ) -> Int {
        var score = (boostWeak ? 4 : 2) * exercise.focusAreas.filter { focus.contains($0) }.count
        if !patterns.isEmpty {
            score += 3 * exercise.movementPatterns.filter { patterns.contains($0) }.count
        }
        if exercise.mobilityMode == .staticHold { score += 1 }
        return score
    }

    // MARK: - Recovery moderation

    private static func filteredPreWorkoutPool(
        catalog: [MobilityExercise],
        recoveryPercent: Int?
    ) -> [MobilityExercise] {
        let pool = catalog.filter { $0.sessionKinds.contains(.preWorkout) }
        guard let r = recoveryPercent, r < 50 else { return pool }
        return pool.filter { ex in
            ex.mobilityMode != .staticHold || (ex.maxHoldSec ?? ex.durationSec) <= 60
        }
    }

    private static func isRecoveryLimited(_ recovery: Int?) -> Bool {
        guard let r = recovery else { return false }
        return r < 67
    }

    // MARK: - Helpers

    private static func priorityAreas(for dayType: PRVNDayType) -> Set<MobilityFocusArea> {
        switch dayType {
        case .heavy:  return [.hips, .ankles, .wrists]
        case .skill:  return [.shoulders, .thoracic, .wrists]
        case .engine: return [.hips, .quads, .hamstrings]
        case .mixed:  return [.hips, .shoulders, .thoracic]
        case .rest:   return [.hips, .hamstrings, .thoracic]
        }
    }

    private static func rationaleForPreWorkout(
        dayType: PRVNDayType,
        patterns: Set<MobilityMovementPattern>,
        priority: Set<MobilityFocusArea>,
        recoveryPercent: Int?,
        targetMinutes: Int
    ) -> String {
        if !patterns.isEmpty {
            let labels = PRVNMovementPatternParser.patternLabels(patterns)
            var text = "~\(targetMinutes) min antes del WOD — movilidad para \(labels) (\(focusLabel(priority)))."
            if let r = recoveryPercent, r < 67 {
                text += " Recuperación \(r)%: más dinámico, menos estático."
            }
            return text
        }
        return "~\(targetMinutes) min — día \(dayType.displayName), foco en \(focusLabel(priority))."
    }

    private static func focusLabel(_ areas: Set<MobilityFocusArea>) -> String {
        areas.sorted { $0.label < $1.label }.map(\.label).joined(separator: ", ")
    }

    private static func focusSummary(
        areas: Set<MobilityFocusArea>,
        patterns: Set<MobilityMovementPattern>
    ) -> String {
        var parts = areas.sorted { $0.label < $1.label }.map(\.label)
        if !patterns.isEmpty {
            parts.append(PRVNMovementPatternParser.patternLabels(patterns))
        }
        return parts.joined(separator: " · ")
    }

    private static func makeRoutine(
        kind: MobilitySessionKind,
        exercises: [MobilityExercise],
        rationale: String,
        focusAreas: Set<MobilityFocusArea>,
        patterns: Set<MobilityMovementPattern>
    ) -> MobilityRoutine {
        let ordered = orderExercises(exercises, sessionKind: kind)
        let steps = ordered.flatMap { routineSteps(for: $0, sessionKind: kind) }
        let totalSec = steps.reduce(0) { $0 + $1.guidedDurationSec }
        let minutes = max(1, Int((Double(totalSec) / 60.0).rounded()))
        return MobilityRoutine(
            sessionKind: kind,
            steps: steps,
            estimatedMinutes: minutes,
            rationale: rationale,
            focusSummary: focusSummary(areas: focusAreas, patterns: patterns)
        )
    }

    private static func routineSteps(
        for exercise: MobilityExercise,
        sessionKind: MobilitySessionKind
    ) -> [MobilityRoutineStep] {
        if exercise.isBilateral {
            let perSide = MobilityTiming.bilateralSideDurationSec
            return [
                MobilityRoutineStep(exercise: exercise, guidedDurationSec: perSide, side: .left),
                MobilityRoutineStep(exercise: exercise, guidedDurationSec: perSide, side: .right),
            ]
        }
        return [
            MobilityRoutineStep(
                exercise: exercise,
                guidedDurationSec: MobilityTiming.guidedDurationSecUnilateral(
                    for: exercise,
                    sessionKind: sessionKind
                ),
                side: nil
            ),
        ]
    }

    /// Orden: activación → dinámico → estático (pre-entreno); estático primero (noche).
    private static func orderExercises(
        _ exercises: [MobilityExercise],
        sessionKind: MobilitySessionKind
    ) -> [MobilityExercise] {
        let modeOrder: [MobilityMode: Int] = {
            switch sessionKind {
            case .preSleep:
                return [.staticHold: 0, .dynamic: 1, .activation: 2]
            case .postWorkout:
                return [.staticHold: 0, .dynamic: 1, .activation: 2]
            case .preWorkout:
                return [.activation: 0, .dynamic: 1, .staticHold: 2]
            case .daily:
                return [.dynamic: 0, .activation: 1, .staticHold: 2]
            }
        }()
        return exercises.sorted { a, b in
            let oa = modeOrder[a.mobilityMode] ?? 9
            let ob = modeOrder[b.mobilityMode] ?? 9
            if oa != ob { return oa < ob }
            return a.id < b.id
        }
    }

    private static func pickScored(
        pool: [MobilityExercise],
        count: Int,
        seed: String,
        score: (MobilityExercise) -> Int
    ) -> [MobilityExercise] {
        guard count > 0, !pool.isEmpty else { return [] }
        let ranked = pool
            .map { (ex: $0, s: score($0)) }
            .sorted { a, b in
                if a.s != b.s { return a.s > b.s }
                return a.ex.id < b.ex.id
            }
            .map(\.ex)
        let withScore = ranked.filter { score($0) > 0 }
        let source = withScore.isEmpty ? ranked : withScore
        return rotatePick(pool: source, count: count, seed: seed)
    }

    private static func pickFromFocus(
        pool: [MobilityExercise],
        focus: Set<MobilityFocusArea>,
        count: Int,
        seed: String
    ) -> [MobilityExercise] {
        pickScored(pool: pool, count: count, seed: seed) { ex in
            ex.focusAreas.filter { focus.contains($0) }.count
        }
    }

    private static func rotatePick(
        pool: [MobilityExercise],
        count: Int,
        seed: String
    ) -> [MobilityExercise] {
        guard count > 0, !pool.isEmpty else { return [] }
        let sorted = pool.sorted { $0.id < $1.id }
        let start = abs(seed.hashValue) % sorted.count
        var result: [MobilityExercise] = []
        var idx = start
        while result.count < count {
            let ex = sorted[idx % sorted.count]
            if !result.contains(where: { $0.id == ex.id }) {
                result.append(ex)
            }
            idx += 1
            if idx - start >= sorted.count * 2 { break }
        }
        return result
    }
}
