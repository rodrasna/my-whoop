import Foundation

// MARK: - SleepCheckInStore
// Cuestionario matutino local (UserDefaults) con merge opcional desde el servidor.

@MainActor
final class SleepCheckInStore: ObservableObject {
    static let shared = SleepCheckInStore()

    private static let storageKey = "com.openwhoop.sleepCheckIns.v1"

    @Published private(set) var entries: [String: SleepCheckIn] = [:]

    private init() {
        load()
    }

    func entry(forDayKey dayKey: String) -> SleepCheckIn? {
        entries[dayKey]
    }

    func hasEntry(forDayKey dayKey: String) -> Bool {
        entries[dayKey] != nil
    }

    func save(_ checkIn: SleepCheckIn) {
        entries[checkIn.dayKey] = checkIn
        persist()
    }

    func delete(dayKey: String) {
        entries.removeValue(forKey: dayKey)
        persist()
    }

    /// Entradas recientes ordenadas por día (más reciente primero).
    func recentEntries(limit: Int = 14) -> [SleepCheckIn] {
        entries.values
            .sorted { $0.dayKey > $1.dayKey }
            .prefix(limit)
            .map { $0 }
    }

    /// Fusiona respuestas del servidor: gana la más reciente por `savedAt`.
    func mergeFromServer(_ remote: [SleepCheckIn]) {
        guard !remote.isEmpty else { return }
        var changed = false
        for item in remote {
            if let local = entries[item.dayKey] {
                if item.savedAt > local.savedAt {
                    entries[item.dayKey] = item
                    changed = true
                }
            } else {
                entries[item.dayKey] = item
                changed = true
            }
        }
        if changed { persist() }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: SleepCheckIn].self, from: data) else {
            entries = [:]
            return
        }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
