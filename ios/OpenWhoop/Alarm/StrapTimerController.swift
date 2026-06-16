import Foundation
import UserNotifications

// MARK: - StrapTimerController
// Cuenta atrás en el teléfono; al terminar vibra la pulsera (mismo patrón que la alarma).

@MainActor
final class StrapTimerController: ObservableObject {
    static let shared = StrapTimerController()

    private static let endEpochKey = "com.openwhoop.strapTimer.endEpoch"
    private static let notificationId = "com.openwhoop.strapTimer.done"

    @Published private(set) var remainingSeconds = 0
    @Published private(set) var isRunning = false
    @Published var selectedMinutes = 5

    private var endDate: Date?
    private var tickTask: Task<Void, Never>?
    private weak var live: LiveViewModel?

    private init() {}

    func attach(live: LiveViewModel) {
        self.live = live
        restoreIfNeeded()
    }

    func start() {
        cancel(scheduleOnly: true)
        let seconds = max(1, selectedMinutes * 60)
        let end = Date().addingTimeInterval(TimeInterval(seconds))
        endDate = end
        remainingSeconds = seconds
        isRunning = true
        UserDefaults.standard.set(end.timeIntervalSince1970, forKey: Self.endEpochKey)
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
        scheduleLocalNotification(at: end)
        startTicking()
    }

    func cancel(scheduleOnly: Bool = false) {
        tickTask?.cancel()
        tickTask = nil
        endDate = nil
        remainingSeconds = 0
        isRunning = false
        UserDefaults.standard.removeObject(forKey: Self.endEpochKey)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        if !scheduleOnly {
            live?.stopHaptics()
        }
    }

    private func restoreIfNeeded() {
        let epoch = UserDefaults.standard.double(forKey: Self.endEpochKey)
        guard epoch > 0 else { return }
        let end = Date(timeIntervalSince1970: epoch)
        if end <= Date() {
            UserDefaults.standard.removeObject(forKey: Self.endEpochKey)
            finish()
            return
        }
        endDate = end
        remainingSeconds = max(0, Int(ceil(end.timeIntervalSinceNow)))
        isRunning = true
        startTicking()
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task {
            while !Task.isCancelled, let end = endDate {
                let left = Int(ceil(end.timeIntervalSinceNow))
                if left <= 0 { break }
                remainingSeconds = left
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if !Task.isCancelled { finish() }
        }
    }

    private func finish() {
        tickTask?.cancel()
        tickTask = nil
        endDate = nil
        remainingSeconds = 0
        isRunning = false
        UserDefaults.standard.removeObject(forKey: Self.endEpochKey)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        live?.testAlarmBuzz()
    }

    private func scheduleLocalNotification(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Temporizador"
        content.body = "Tiempo terminado"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.notificationId,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func formattedRemaining(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
