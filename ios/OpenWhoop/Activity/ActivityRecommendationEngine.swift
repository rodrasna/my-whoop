import Foundation

// MARK: - ActivityRecommendationEngine
// Recomendaciones diarias: capacidad (recovery) + demanda (PRVN) + gap de strain + sensación subjetiva.

enum ActivityRecommendationKind: String, Equatable {
    case push
    case maintain
    case modify
    case activeRecovery
    case mobilityPreWOD
    case mobilityPostWorkout
    case mobilityDaily
    case rest
    case sedentaryBreak
    case windDown
}

struct ActivityRecommendationAction: Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let durationMinutes: Int?
    let systemImage: String
    let mobilitySession: MobilitySessionKind?

    init(
        title: String,
        detail: String,
        durationMinutes: Int? = nil,
        systemImage: String,
        mobilitySession: MobilitySessionKind? = nil
    ) {
        self.id = title
        self.title = title
        self.detail = detail
        self.durationMinutes = durationMinutes
        self.systemImage = systemImage
        self.mobilitySession = mobilitySession
    }
}

struct ActivityRecommendation: Equatable {
    let kind: ActivityRecommendationKind
    let primaryTitle: String
    let rationale: String
    let actions: [ActivityRecommendationAction]
    let strainTargetMin: Double?
    let strainTargetMax: Double?

    /// Sesión de Movilidad sugerida para el CTA principal de la tarjeta.
    var suggestedMobilitySession: MobilitySessionKind? {
        switch kind {
        case .mobilityPreWOD: return .preWorkout
        case .mobilityPostWorkout: return .postWorkout
        case .mobilityDaily: return .daily
        case .windDown: return .preSleep
        case .modify, .activeRecovery, .rest:
            return actions.compactMap(\.mobilitySession).first
        default:
            return actions.compactMap(\.mobilitySession).first
        }
    }
}

struct ActivityRecommendationContext: Equatable {
    var dayKey: String
    var recoveryPercent: Int?
    var strainToday: Double?
    var strainYesterday: Double?
    var prvnDay: PRVNDayProgram?
    var morningFeeling: MorningFeeling?
    var activityCountToday: Int
    var trainingBoutCountToday: Int
    var hourOfDay: Int
    var isToday: Bool
    /// Bloques PRVN que el usuario marcó como hechos hoy (vacío = todos los no-warmup).
    var blocksDone: [ProgramBlockKind] = []
    /// Sesiones de movilidad ya completadas hoy (rutina guiada).
    var completedMobilitySessions: Set<MobilitySessionKind> = []
    /// Usuario marcó descanso explícito en el plan del día.
    var isRestDay: Bool = false
}

enum ActivityRecommendationEngine {

    private static func mobilityMinutes(
        kind: MobilitySessionKind,
        recoveryPercent: Int? = nil
    ) -> Int {
        MobilityTiming.sessionTarget(kind: kind, recoveryPercent: recoveryPercent).midpointMinutes
    }

    private static func mobilityDetail(
        kind: MobilitySessionKind,
        recoveryPercent: Int? = nil,
        suffix: String = ""
    ) -> String {
        let target = MobilityTiming.sessionTarget(kind: kind, recoveryPercent: recoveryPercent)
        let minM = target.minSec / 60
        let maxM = target.maxSec / 60
        let base = "Estiramientos guiados · \(minM)–\(maxM) min en la app"
        return suffix.isEmpty ? base : "\(base). \(suffix)"
    }

    static func recommend(context: ActivityRecommendationContext) -> ActivityRecommendation? {
        guard context.isToday else { return nil }
        guard let raw = recommendImpl(context: context) else { return nil }
        return polishMobility(raw, context: context)
    }

    private static func recommendImpl(context: ActivityRecommendationContext) -> ActivityRecommendation? {

        let tier = effectiveRecoveryTier(
            recovery: context.recoveryPercent,
            feeling: context.morningFeeling
        )
        let targets = strainTarget(for: tier)
        let strain = context.strainToday ?? 0
        let prvn = context.prvnDay
        let patterns = PRVNMovementPatternParser.patterns(
            from: prvn,
            blocksDone: context.blocksDone
        )
        let hasPRVN = prvn != nil && prvn?.dayType != .rest

        if context.isRestDay {
            return restDayRecommendation(
                tier: tier,
                targets: targets,
                strain: strain,
                recoveryPercent: context.recoveryPercent
            )
        }

        if context.hourOfDay >= 20, strain >= 10 {
            return windDown(strain: strain, recoveryPercent: context.recoveryPercent)
        }

        if context.activityCountToday == 0,
           context.trainingBoutCountToday == 0,
           context.hourOfDay >= 14 {
            return sedentaryBreak(tier: tier)
        }

        if let prvn, prvn.dayType == .rest {
            return restDayRecommendation(
                tier: tier,
                targets: targets,
                strain: strain,
                recoveryPercent: context.recoveryPercent
            )
        }

        if tier == .low {
            if hasPRVN, let prvn, prvn.dayType != .rest {
                return modifyForLowRecovery(
                    prvn: prvn,
                    targets: targets,
                    strain: strain,
                    recoveryPercent: context.recoveryPercent
                )
            }
            return activeRecoveryRecommendation(
                targets: targets,
                strain: strain,
                reason: "Recuperación baja",
                recoveryPercent: context.recoveryPercent
            )
        }

        if hasPRVN, let prvn {
            let minRec = prvn.dayType.suggestedRecoveryMin
            if let rec = context.recoveryPercent, rec < minRec, tier != .high {
                return modifyForLowRecovery(
                    prvn: prvn,
                    targets: targets,
                    strain: strain,
                    recoveryPercent: context.recoveryPercent
                )
            }
        }

        if strain >= (targets.max + 1.5) {
            return postStrainWindDown(strain: strain)
        }

        if strain < targets.min - 2, tier == .high {
            return fillStrainGap(
                targets: targets,
                strain: strain,
                prvn: prvn,
                patterns: patterns,
                recoveryPercent: context.recoveryPercent
            )
        }

        if hasPRVN, context.trainingBoutCountToday == 0, context.hourOfDay < 18,
           !context.completedMobilitySessions.contains(.preWorkout) {
            return preWorkoutRecommendation(
                prvn: prvn!,
                tier: tier,
                patterns: patterns,
                targets: targets,
                recoveryPercent: context.recoveryPercent
            )
        }

        if context.trainingBoutCountToday > 0,
           context.hourOfDay < 20,
           !context.completedMobilitySessions.contains(.postWorkout) {
            return postWorkoutRecommendation(
                patterns: patterns,
                targets: targets,
                strain: strain,
                recoveryPercent: context.recoveryPercent
            )
        }

        switch tier {
        case .high:
            return pushRecommendation(prvn: prvn, targets: targets, strain: strain, patterns: patterns)
        case .medium:
            return maintainRecommendation(prvn: prvn, targets: targets, strain: strain)
        case .low:
            return activeRecoveryRecommendation(
                targets: targets,
                strain: strain,
                reason: "Recuperación limitada",
                recoveryPercent: context.recoveryPercent
            )
        }
    }

    private static func polishMobility(
        _ rec: ActivityRecommendation,
        context: ActivityRecommendationContext
    ) -> ActivityRecommendation {
        ActivityRecommendation(
            kind: rec.kind,
            primaryTitle: rec.primaryTitle,
            rationale: rec.rationale,
            actions: filterMobilityActions(rec.actions, completed: context.completedMobilitySessions),
            strainTargetMin: rec.strainTargetMin,
            strainTargetMax: rec.strainTargetMax
        )
    }

    // MARK: - Recovery tiers

    enum RecoveryTier: Equatable {
        case high, medium, low
    }

    static func effectiveRecoveryTier(
        recovery: Int?,
        feeling: MorningFeeling?
    ) -> RecoveryTier {
        var tier = tierFromRecovery(recovery)
        if let feeling, feeling.rawValue <= 2 {
            tier = downgrade(tier)
        }
        return tier
    }

    private static func tierFromRecovery(_ recovery: Int?) -> RecoveryTier {
        guard let r = recovery else { return .medium }
        if r >= 67 { return .high }
        if r >= 34 { return .medium }
        return .low
    }

    private static func downgrade(_ tier: RecoveryTier) -> RecoveryTier {
        switch tier {
        case .high: return .medium
        case .medium: return .low
        case .low: return .low
        }
    }

    struct StrainTarget {
        let min: Double
        let max: Double
    }

    static func strainTarget(for tier: RecoveryTier) -> StrainTarget {
        switch tier {
        case .high:   return StrainTarget(min: 12, max: 16)
        case .medium: return StrainTarget(min: 8, max: 12)
        case .low:    return StrainTarget(min: 4, max: 8)
        }
    }

    // MARK: - Builders

    private static func pushRecommendation(
        prvn: PRVNDayProgram?,
        targets: StrainTarget,
        strain: Double,
        patterns: Set<MobilityMovementPattern>
    ) -> ActivityRecommendation {
        let typeLabel = prvn?.dayType.displayName ?? "entreno"
        var rationale = "Recuperación alta — buen día para exigirte (objetivo strain \(formatStrain(targets.min))–\(formatStrain(targets.max)))."
        if !patterns.isEmpty {
            rationale += " Patrones: \(PRVNMovementPatternParser.patternLabels(patterns))."
        }
        return ActivityRecommendation(
            kind: .push,
            primaryTitle: "Puedes apretar hoy",
            rationale: rationale,
            actions: [
                ActivityRecommendationAction(
                    title: "Sigue el plan \(typeLabel)",
                    detail: "Strain actual \(formatStrain(strain)) — margen para sesión exigente.",
                    systemImage: "flame.fill"
                ),
            ],
            strainTargetMin: targets.min,
            strainTargetMax: targets.max
        )
    }

    private static func maintainRecommendation(
        prvn: PRVNDayProgram?,
        targets: StrainTarget,
        strain: Double
    ) -> ActivityRecommendation {
        let typeLabel = prvn?.dayType.displayName ?? "moderado"
        return ActivityRecommendation(
            kind: .maintain,
            primaryTitle: "Intensidad moderada",
            rationale: "Recuperación media — entrena \(typeLabel) pero baja un 20–30% si notas fatiga (strain objetivo \(formatStrain(targets.min))–\(formatStrain(targets.max))).",
            actions: [
                ActivityRecommendationAction(
                    title: "Entreno ajustado",
                    detail: "Strain \(formatStrain(strain)). Evita PRs; prioriza técnica.",
                    systemImage: "gauge.with.dots.needle.50percent"
                ),
            ],
            strainTargetMin: targets.min,
            strainTargetMax: targets.max
        )
    }

    private static func filterMobilityActions(
        _ actions: [ActivityRecommendationAction],
        completed: Set<MobilitySessionKind>
    ) -> [ActivityRecommendationAction] {
        actions.filter { action in
            guard let session = action.mobilitySession else { return true }
            return !completed.contains(session)
        }
    }

    private static func modifyForLowRecovery(
        prvn: PRVNDayProgram,
        targets: StrainTarget,
        strain: Double,
        recoveryPercent: Int?
    ) -> ActivityRecommendation {
        ActivityRecommendation(
            kind: .modify,
            primaryTitle: "Adapta el día \(prvn.dayType.displayName)",
            rationale: "Tu recuperación no encaja con un día exigente — versión reducida o técnica ligera.",
            actions: [
                ActivityRecommendationAction(
                    title: "Baja carga o volumen",
                    detail: "Strain \(formatStrain(strain)). Objetivo hoy: ≤\(formatStrain(targets.max)).",
                    systemImage: "exclamationmark.triangle.fill"
                ),
                ActivityRecommendationAction(
                    title: "Movilidad pre-entreno",
                    detail: mobilityDetail(
                        kind: .preWorkout,
                        recoveryPercent: recoveryPercent,
                        suffix: "Dinámico antes de tocar barra."
                    ),
                    durationMinutes: mobilityMinutes(kind: .preWorkout, recoveryPercent: recoveryPercent),
                    systemImage: "figure.flexibility",
                    mobilitySession: .preWorkout
                ),
            ],
            strainTargetMin: targets.min,
            strainTargetMax: targets.max
        )
    }

    private static func activeRecoveryRecommendation(
        targets: StrainTarget,
        strain: Double,
        reason: String,
        recoveryPercent: Int?
    ) -> ActivityRecommendation {
        ActivityRecommendation(
            kind: .activeRecovery,
            primaryTitle: "Recuperación activa",
            rationale: "\(reason) — movimiento suave ayuda sin añadir carga (strain objetivo \(formatStrain(targets.min))–\(formatStrain(targets.max))).",
            actions: [
                ActivityRecommendationAction(
                    title: "Caminata suave",
                    detail: "20–30 min; deberías poder hablar cómodo.",
                    durationMinutes: 25,
                    systemImage: "figure.walk"
                ),
                ActivityRecommendationAction(
                    title: "Movilidad diaria",
                    detail: mobilityDetail(
                        kind: .daily,
                        recoveryPercent: recoveryPercent,
                        suffix: "Rutina suave en la pestaña Movilidad."
                    ),
                    durationMinutes: mobilityMinutes(kind: .daily, recoveryPercent: recoveryPercent),
                    systemImage: "figure.flexibility",
                    mobilitySession: .daily
                ),
            ],
            strainTargetMin: targets.min,
            strainTargetMax: targets.max
        )
    }

    private static func preWorkoutRecommendation(
        prvn: PRVNDayProgram,
        tier: RecoveryTier,
        patterns: Set<MobilityMovementPattern>,
        targets: StrainTarget,
        recoveryPercent: Int?
    ) -> ActivityRecommendation {
        let patternText = patterns.isEmpty
            ? "las demandas del día"
            : PRVNMovementPatternParser.patternLabels(patterns)
        let mobilityMin = mobilityMinutes(kind: .preWorkout, recoveryPercent: recoveryPercent)
        return ActivityRecommendation(
            kind: .mobilityPreWOD,
            primaryTitle: "Prepara el \(prvn.dayType.displayName)",
            rationale: "Antes del WOD — movilidad para \(patternText).",
            actions: [
                ActivityRecommendationAction(
                    title: "Pre-entreno en Movilidad",
                    detail: mobilityDetail(
                        kind: .preWorkout,
                        recoveryPercent: recoveryPercent,
                        suffix: "Sesión dinámica adaptada al programa."
                    ),
                    durationMinutes: mobilityMin,
                    systemImage: "figure.flexibility",
                    mobilitySession: .preWorkout
                ),
            ],
            strainTargetMin: targets.min,
            strainTargetMax: targets.max
        )
    }

    private static func fillStrainGap(
        targets: StrainTarget,
        strain: Double,
        prvn: PRVNDayProgram?,
        patterns: Set<MobilityMovementPattern>,
        recoveryPercent: Int?
    ) -> ActivityRecommendation {
        let gap = targets.min - strain
        var secondary = ActivityRecommendationAction(
            title: "Movilidad diaria",
            detail: mobilityDetail(
                kind: .daily,
                recoveryPercent: recoveryPercent,
                suffix: "Mantén articulaciones en rango."
            ),
            durationMinutes: mobilityMinutes(kind: .daily, recoveryPercent: recoveryPercent),
            systemImage: "figure.flexibility",
            mobilitySession: .daily
        )
        if !patterns.isEmpty {
            secondary = ActivityRecommendationAction(
                title: "Movilidad pre-entreno",
                detail: mobilityDetail(
                    kind: .preWorkout,
                    recoveryPercent: recoveryPercent,
                    suffix: "Si entrenas después: \(PRVNMovementPatternParser.patternLabels(patterns))."
                ),
                durationMinutes: mobilityMinutes(kind: .preWorkout, recoveryPercent: recoveryPercent),
                systemImage: "figure.flexibility",
                mobilitySession: .preWorkout
            )
        }
        return ActivityRecommendation(
            kind: .maintain,
            primaryTitle: "Te falta movimiento ligero",
            rationale: "Strain \(formatStrain(strain)) — te quedan ~\(formatStrain(gap)) para el objetivo del día.",
            actions: [
                ActivityRecommendationAction(
                    title: "Caminata o bici suave",
                    detail: "Zona fácil 20–40 min sin apretar.",
                    durationMinutes: 30,
                    systemImage: "figure.walk"
                ),
                secondary,
            ],
            strainTargetMin: targets.min,
            strainTargetMax: targets.max
        )
    }

    private static func restDayRecommendation(
        tier: RecoveryTier,
        targets: StrainTarget,
        strain: Double,
        recoveryPercent: Int?
    ) -> ActivityRecommendation {
        ActivityRecommendation(
            kind: tier == .low ? .rest : .mobilityDaily,
            primaryTitle: tier == .low ? "Descanso prioritario" : "Día de descanso activo",
            rationale: tier == .low
                ? "PRVN descanso y recuperación baja — prioriza sueño e hidratación."
                : "Día libre en PRVN — movilidad y caminata suave.",
            actions: [
                ActivityRecommendationAction(
                    title: "Caminata opcional",
                    detail: "15–20 min si te apetece moverte.",
                    durationMinutes: 20,
                    systemImage: "figure.walk"
                ),
                ActivityRecommendationAction(
                    title: "Rutina diaria de movilidad",
                    detail: mobilityDetail(
                        kind: .daily,
                        recoveryPercent: recoveryPercent,
                        suffix: "Mejora rangos sin fatigar."
                    ),
                    durationMinutes: mobilityMinutes(kind: .daily, recoveryPercent: recoveryPercent),
                    systemImage: "figure.flexibility",
                    mobilitySession: .daily
                ),
            ],
            strainTargetMin: targets.min,
            strainTargetMax: targets.max
        )
    }

    private static func sedentaryBreak(tier: RecoveryTier) -> ActivityRecommendation {
        ActivityRecommendation(
            kind: .sedentaryBreak,
            primaryTitle: "Rompe el sedentarismo",
            rationale: "Sin actividad detectada hoy — un poco de movimiento ligero suma.",
            actions: [
                ActivityRecommendationAction(
                    title: "Caminata 5–10 min",
                    detail: "Interrumpe estar sentado; ideal cada ~30 min.",
                    durationMinutes: 8,
                    systemImage: "figure.walk"
                ),
            ],
            strainTargetMin: strainTarget(for: tier).min,
            strainTargetMax: strainTarget(for: tier).max
        )
    }

    private static func postWorkoutRecommendation(
        patterns: Set<MobilityMovementPattern>,
        targets: StrainTarget,
        strain: Double,
        recoveryPercent: Int?
    ) -> ActivityRecommendation {
        let patternText = patterns.isEmpty
            ? "las zonas que has cargado"
            : PRVNMovementPatternParser.patternLabels(patterns)
        return ActivityRecommendation(
            kind: .mobilityPostWorkout,
            primaryTitle: "Enfría y descomprime",
            rationale: "Ya entrenaste hoy (strain \(formatStrain(strain))) — estiramientos suaves para \(patternText).",
            actions: [
                ActivityRecommendationAction(
                    title: "Post-entreno en Movilidad",
                    detail: mobilityDetail(
                        kind: .postWorkout,
                        recoveryPercent: recoveryPercent,
                        suffix: "Estáticos suaves; no busques más rango."
                    ),
                    durationMinutes: mobilityMinutes(kind: .postWorkout, recoveryPercent: recoveryPercent),
                    systemImage: "figure.cooldown",
                    mobilitySession: .postWorkout
                ),
            ],
            strainTargetMin: targets.min,
            strainTargetMax: targets.max
        )
    }

    private static func windDown(strain: Double, recoveryPercent: Int?) -> ActivityRecommendation {
        ActivityRecommendation(
            kind: .windDown,
            primaryTitle: "Cierra el día",
            rationale: "Strain \(formatStrain(strain)) — baja el sistema antes de dormir.",
            actions: [
                ActivityRecommendationAction(
                    title: "Movilidad nocturna",
                    detail: mobilityDetail(
                        kind: .preSleep,
                        recoveryPercent: recoveryPercent,
                        suffix: "Sesión suave en Movilidad → Noche."
                    ),
                    durationMinutes: mobilityMinutes(kind: .preSleep, recoveryPercent: recoveryPercent),
                    systemImage: "moon.stars.fill",
                    mobilitySession: .preSleep
                ),
            ],
            strainTargetMin: nil,
            strainTargetMax: nil
        )
    }

    private static func postStrainWindDown(strain: Double) -> ActivityRecommendation {
        ActivityRecommendation(
            kind: .activeRecovery,
            primaryTitle: "Objetivo de strain cumplido",
            rationale: "Strain \(formatStrain(strain)) — solo movimiento suave el resto del día.",
            actions: [
                ActivityRecommendationAction(
                    title: "Caminata o estiramientos suaves",
                    detail: "Sin más carga de entreno.",
                    durationMinutes: 15,
                    systemImage: "figure.walk"
                ),
            ],
            strainTargetMin: nil,
            strainTargetMax: nil
        )
    }

    private static func formatStrain(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
