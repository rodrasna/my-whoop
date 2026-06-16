import Foundation
import SwiftUI

// MARK: - WorkoutDayPlan
// Plan manual del entreno de un día: qué bout es el principal, tipo, bloques hechos y notas.

struct WorkoutDayPlan: Codable, Equatable {
    var primaryWorkoutId: String?
    var activityType: ActivityType?
    var crossfitStyle: CrossFitSessionStyle?
    /// Bloques que realmente hiciste (p. ej. solo WOD en un clasificatorio).
    var blocksDone: [ProgramBlockKind] = []
    var note: String?

    var hasContent: Bool {
        primaryWorkoutId != nil
            || activityType != nil
            || crossfitStyle != nil
            || !blocksDone.isEmpty
            || !(note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

struct ResolvedDayWorkout: Equatable {
    let primary: Workout?
    let activityType: ActivityType?
    let crossfitStyle: CrossFitSessionStyle?
    let blocksDone: [ProgramBlockKind]
    let note: String?
    let isUserDefined: Bool
}

// MARK: - WorkoutDayPlanStore

@MainActor
final class WorkoutDayPlanStore: ObservableObject {

    private static let key = "com.openwhoop.workoutDayPlans.v1"

    @Published private(set) var plans: [String: WorkoutDayPlan] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: WorkoutDayPlan].self, from: data) {
            plans = decoded
        }
    }

    func plan(for dayKey: String) -> WorkoutDayPlan? {
        plans[dayKey]
    }

    func set(_ plan: WorkoutDayPlan?, for dayKey: String) {
        if let plan, plan.hasContent {
            plans[dayKey] = plan
        } else {
            plans.removeValue(forKey: dayKey)
        }
        persist()
    }

    /// Resuelve el entreno del día combinando plan manual, etiquetas y PRVN.
    func resolve(
        dayKey: String,
        workouts: [Workout],
        labelStore: ActivityLabelStore,
        prvnDay: PRVNDayProgram?,
        isTrainingBout: (Workout) -> Bool
    ) -> ResolvedDayWorkout {
        let saved = plans[dayKey]
        let candidates = workouts.sorted { ($0.strain ?? 0) > ($1.strain ?? 0) }

        let primary: Workout? = {
            if let id = saved?.primaryWorkoutId {
                return workouts.first { $0.id == id }
            }
            return candidates.first(where: isTrainingBout) ?? candidates.first
        }()

        let activityType: ActivityType? = {
            if let t = saved?.activityType { return t }
            if let primary { return labelStore.effectiveType(for: primary) }
            return nil
        }()

        let crossfitStyle: CrossFitSessionStyle? = {
            if let s = saved?.crossfitStyle { return s }
            if let primary { return labelStore.sessionStyle(for: primary) }
            return nil
        }()

        let blocksDone: [ProgramBlockKind] = {
            if let saved, !saved.blocksDone.isEmpty { return saved.blocksDone.sorted(by: blockSort) }
            if let prvn = prvnDay {
                return prvn.blocks.map(\.kind).filter { $0 != .other }.sorted(by: blockSort)
            }
            return []
        }()

        let note = saved?.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        return ResolvedDayWorkout(
            primary: primary,
            activityType: activityType,
            crossfitStyle: crossfitStyle,
            blocksDone: blocksDone,
            note: note,
            isUserDefined: saved?.hasContent == true
        )
    }

    private func blockSort(_ a: ProgramBlockKind, _ b: ProgramBlockKind) -> Bool {
        let order: [ProgramBlockKind] = [.warmup, .strength, .metcon, .accessory, .other]
        return (order.firstIndex(of: a) ?? 99) < (order.firstIndex(of: b) ?? 99)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(plans) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
