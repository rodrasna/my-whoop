import Foundation
import Combine

// MARK: - Mobility assessment (mini-test v1 local)
// Autoevaluación 1–5 por zona; las áreas débiles (≤2) priorizan la rutina diaria.

struct MobilityAssessmentScores: Codable, Equatable {
    var scores: [MobilityFocusArea: Int]
    var completedAt: Date?

    init(scores: [MobilityFocusArea: Int] = [:], completedAt: Date? = nil) {
        self.scores = scores
        self.completedAt = completedAt
    }

    func score(for area: MobilityFocusArea) -> Int? {
        scores[area]
    }

    /// Áreas con rigidez marcada (1–2 en escala 1–5).
    func weakAreas(threshold: Int = 2) -> Set<MobilityFocusArea> {
        Set(scores.compactMap { area, value in
            value <= threshold ? area : nil
        })
    }

    var isComplete: Bool {
        MobilityFocusArea.allCases.allSatisfy { scores[$0] != nil }
    }

    var ratedCount: Int {
        MobilityFocusArea.allCases.filter { scores[$0] != nil }.count
    }

    var totalAreas: Int { MobilityFocusArea.allCases.count }
}

@MainActor
final class MobilityAssessmentStore: ObservableObject {
    static let shared = MobilityAssessmentStore()

    private static let scoresKey = "com.openwhoop.mobility.assessment.v1"
    private static let snoozeKey = "com.openwhoop.mobility.assessment.snoozeUntil"

    private let defaults: UserDefaults

    @Published private(set) var scores: MobilityAssessmentScores
    @Published private(set) var onboardingSnoozedUntil: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.scoresKey),
           let decoded = try? JSONDecoder().decode(MobilityAssessmentScores.self, from: data) {
            scores = decoded
        } else {
            scores = MobilityAssessmentScores()
        }
        onboardingSnoozedUntil = defaults.object(forKey: Self.snoozeKey) as? Date
    }

    var shouldShowOnboarding: Bool {
        guard !scores.isComplete else { return false }
        if let until = onboardingSnoozedUntil, Date() < until { return false }
        return true
    }

    func setScore(_ value: Int, for area: MobilityFocusArea) {
        var next = scores.scores
        next[area] = min(5, max(1, value))
        var completedAt = scores.completedAt
        if MobilityFocusArea.allCases.allSatisfy({ next[$0] != nil }) {
            completedAt = Date()
        }
        scores = MobilityAssessmentScores(scores: next, completedAt: completedAt)
        persist()
    }

    func weakAreas() -> Set<MobilityFocusArea> {
        scores.weakAreas()
    }

    func snoozeOnboarding(days: Int = 7) {
        let until = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        onboardingSnoozedUntil = until
        defaults.set(until, forKey: Self.snoozeKey)
    }

    func clearOnboardingSnooze() {
        onboardingSnoozedUntil = nil
        defaults.removeObject(forKey: Self.snoozeKey)
    }

    func resetForTesting() {
        scores = MobilityAssessmentScores()
        onboardingSnoozedUntil = nil
        defaults.removeObject(forKey: Self.scoresKey)
        defaults.removeObject(forKey: Self.snoozeKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(scores) else { return }
        defaults.set(data, forKey: Self.scoresKey)
    }
}
