import Foundation

// MARK: - Coach LLM preferences (task-09 Phase B)

enum CoachLLMSettings {
    private static let enabledKey = "com.openwhoop.coach.llm.enabled"
    private static let includeNoteKey = "com.openwhoop.coach.llm.includeNote"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// When enabled, the server may include the day-plan note in the LLM prompt.
    static var includeDayNote: Bool {
        get { UserDefaults.standard.object(forKey: includeNoteKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: includeNoteKey) }
    }
}

struct CoachNarrativeResponse: Codable, Equatable {
    let narrative: String
    let source: String
    let day: String?
}
