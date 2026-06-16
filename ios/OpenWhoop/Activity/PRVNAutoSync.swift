import Foundation

// MARK: - PRVNAutoSync
// Domingo: descarga la semana que empieza el lunes siguiente (cuando publican en PRVN).

enum PRVNAutoSync {
    private static let lastWeekKey = "com.openwhoop.prvn.autoSyncWeek"

    /// Lunes de la semana a sincronizar. Domingo → próximo lunes; resto → lunes actual.
    static func weekMondayToSync(from date: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        if _isSunday(start, calendar: calendar),
           let nextMonday = calendar.date(byAdding: .day, value: 1, to: start) {
            return nextMonday
        }
        return PRVNProgramStore.monday(containing: start, calendar: calendar)
    }

    /// Auto-sync solo domingos, una vez por semana importada.
    static func shouldRunAutoSync(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard _isSunday(now, calendar: calendar) else { return false }
        let weekKey = PRVNProgramStore.dayKey(for: weekMondayToSync(from: now, calendar: calendar), calendar: calendar)
        return UserDefaults.standard.string(forKey: lastWeekKey) != weekKey
    }

    static func markSynced(weekMonday: Date, calendar: Calendar = .current) {
        let key = PRVNProgramStore.dayKey(for: weekMonday, calendar: calendar)
        UserDefaults.standard.set(key, forKey: lastWeekKey)
    }

  private static func _isSunday(_ date: Date, calendar: Calendar) -> Bool {
        calendar.component(.weekday, from: date) == 1
    }
}
