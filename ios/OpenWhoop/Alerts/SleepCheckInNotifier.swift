import Foundation
import UserNotifications

/// Recordatorio diario para rellenar el cuestionario matutino de sueño.
enum SleepCheckInNotifier {
    private static let enabledKey = "com.openwhoop.sleepCheckIn.reminder.enabled"
    private static let hourKey = "com.openwhoop.sleepCheckIn.reminder.hour"
    private static let minuteKey = "com.openwhoop.sleepCheckIn.reminder.minute"
    private static let notificationId = "sleep-check-in-daily"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var reminderHour: Int {
        get {
            let h = UserDefaults.standard.integer(forKey: hourKey)
            return h == 0 && UserDefaults.standard.object(forKey: hourKey) == nil ? 8 : h
        }
        set { UserDefaults.standard.set(newValue, forKey: hourKey) }
    }

    static var reminderMinute: Int {
        get { UserDefaults.standard.integer(forKey: minuteKey) }
        set { UserDefaults.standard.set(newValue, forKey: minuteKey) }
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Reprograma el recordatorio diario según preferencias actuales.
    static func reschedule(center: UNUserNotificationCenter = .current()) {
        center.removePendingNotificationRequests(withIdentifiers: [notificationId])
        guard isEnabled else { return }

        var date = DateComponents()
        date.hour = reminderHour
        date.minute = reminderMinute

        let content = UNMutableNotificationContent()
        content.title = "¿Cómo dormiste?"
        content.body = "Un minuto para contrastar tu sensación con recovery y sueño de la pulsera."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: notificationId,
                                            content: content,
                                            trigger: trigger)
        center.add(request)
    }

    /// Date picker helper anchored to today's reminder hour/minute.
    static var defaultReminderDate: Date {
        var cal = Calendar.current
        cal.timeZone = .current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = reminderHour
        comps.minute = reminderMinute
        return cal.date(from: comps) ?? Date()
    }
}
