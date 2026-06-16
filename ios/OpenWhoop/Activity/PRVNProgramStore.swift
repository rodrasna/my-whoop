import Foundation
import Combine

// MARK: - PRVNProgramStore

final class PRVNProgramStore: ObservableObject {
    static let shared = PRVNProgramStore()

    private static let storageKey = "com.openwhoop.prvn.week.v1"

    @Published private(set) var week: PRVNWeekProgram?

    init() { load() }

    func importText(_ text: String, weekStart: Date, calendar: Calendar = .current) {
        week = PRVNProgramParser.parse(text, weekStart: weekStart, calendar: calendar)
        save()
    }

    /// Import week text returned by the server SugarWOD sync (`weekStart` = ISO Monday yyyy-MM-dd).
    func importFromServer(pasteText: String, weekStartISO: String, calendar: Calendar = .current) {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        guard let monday = fmt.date(from: weekStartISO) else { return }
        importText(pasteText, weekStart: monday, calendar: calendar)
    }

    func clear() {
        week = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    func program(for date: Date, calendar: Calendar = .current) -> PRVNDayProgram? {
        week?.program(for: date, calendar: calendar)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: calendar.startOfDay(for: date))
    }

    static func monday(containing date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let start = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: start)
        let daysFromMonday = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: -daysFromMonday, to: start) ?? start
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(PRVNWeekProgram.self, from: data) else { return }
        week = decoded
    }

    private func save() {
        guard let week, let data = try? JSONEncoder().encode(week) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
