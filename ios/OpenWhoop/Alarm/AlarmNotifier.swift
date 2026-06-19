import Foundation
import UserNotifications

// MARK: - AlarmNotifier
// Local notification at the programmed wake time — survives force-quit / app swipe-away.
// Does NOT buzz the strap by itself; wakes the user on the phone so they can open the app.
// Strap vibration when the app is dead still depends on SET_ALARM_TIME (firmware).

enum AlarmNotifier {
    static let id = "com.openwhoop.strapAlarm"

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Schedule a one-shot notification at `fireDate`. Replaces any prior alarm notification.
    static func schedule(at fireDate: Date, center: UNUserNotificationCenter = .current()) {
        cancel(center: center)
        guard fireDate.timeIntervalSinceNow > 0 else { return }
        requestAuthorization()

        let content = UNMutableNotificationContent()
        content.title = "Alarma OpenWhoop"
        content.body = "Hora de despertar. Si la pulsera no vibró, abre la app con el strap conectado."
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    static func cancel(center: UNUserNotificationCenter = .current()) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
