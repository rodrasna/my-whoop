import Foundation
import Combine

// MARK: - MobilityCompletionStore
// Registra rutinas guiadas completadas (día + tipo de sesión).

struct MobilityCompletionEntry: Codable, Equatable {
    let dayKey: String
    let sessionKind: MobilitySessionKind
    let exerciseCount: Int
    let completedAt: Date
}

struct MobilityWeekDaySummary: Identifiable, Equatable {
    var id: String { dayKey }
    let dayKey: String
    let weekdayShort: String
    let sessions: [MobilitySessionKind]
    let isToday: Bool
}

enum MobilityCompletionAnalytics {

    static func streak(
        entries: [MobilityCompletionEntry],
        through date: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        var count = 0
        var cursor = calendar.startOfDay(for: date)
        while true {
            let key = MetricsRepository.localDayString(for: cursor)
            let hasSession = entries.contains { $0.dayKey == key }
            if hasSession {
                count += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            } else {
                break
            }
        }
        return count
    }

    static func weekSummary(
        entries: [MobilityCompletionEntry],
        lastDays: Int = 7,
        endingOn date: Date = Date(),
        calendar: Calendar = .current
    ) -> [MobilityWeekDaySummary] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = "EEE"
        let todayKey = MetricsRepository.localDayString(for: date)

        return (0..<lastDays).reversed().compactMap { offset -> MobilityWeekDaySummary? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: date)) else {
                return nil
            }
            let key = MetricsRepository.localDayString(for: day)
            let sessions = entries
                .filter { $0.dayKey == key }
                .map(\.sessionKind)
            let unique = MobilitySessionKind.allCases.filter { sessions.contains($0) }
            return MobilityWeekDaySummary(
                dayKey: key,
                weekdayShort: fmt.string(from: day).capitalized,
                sessions: unique,
                isToday: key == todayKey
            )
        }
    }
}

@MainActor
final class MobilityCompletionStore: ObservableObject {
    static let shared = MobilityCompletionStore()

    private static let storageKey = "com.openwhoop.mobility.completions.v1"

    private let defaults: UserDefaults

    @Published private(set) var entries: [MobilityCompletionEntry] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([MobilityCompletionEntry].self, from: data) {
            entries = decoded
        }
    }

    func markCompleted(sessionKind: MobilitySessionKind, exerciseCount: Int, dayKey: String) {
        let entry = MobilityCompletionEntry(
            dayKey: dayKey,
            sessionKind: sessionKind,
            exerciseCount: exerciseCount,
            completedAt: Date()
        )
        entries.removeAll { $0.dayKey == dayKey && $0.sessionKind == sessionKind }
        entries.append(entry)
        persist()
    }

    func isCompleted(dayKey: String, sessionKind: MobilitySessionKind) -> Bool {
        entries.contains { $0.dayKey == dayKey && $0.sessionKind == sessionKind }
    }

    func entry(dayKey: String, sessionKind: MobilitySessionKind) -> MobilityCompletionEntry? {
        entries.last { $0.dayKey == dayKey && $0.sessionKind == sessionKind }
    }

    func currentStreak(through date: Date = Date()) -> Int {
        MobilityCompletionAnalytics.streak(entries: entries, through: date)
    }

    func weekSummary(lastDays: Int = 7, endingOn date: Date = Date()) -> [MobilityWeekDaySummary] {
        MobilityCompletionAnalytics.weekSummary(entries: entries, lastDays: lastDays, endingOn: date)
    }

    func totalSessions(lastDays: Int = 7, endingOn date: Date = Date()) -> Int {
        let keys = Set(weekSummary(lastDays: lastDays, endingOn: date).map(\.dayKey))
        return entries.filter { keys.contains($0.dayKey) }.count
    }

    func recentEntries(limit: Int = 14) -> [MobilityCompletionEntry] {
        entries.sorted { $0.completedAt > $1.completedAt }.prefix(limit).map { $0 }
    }

    func resetForTesting() {
        entries = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
