import Foundation

// MARK: - StrapAlarmScheduler
// Fires the same haptic path as "Probar alarma" (testAlarmBuzz) at the programmed time.
//
// SET_ALARM_TIME (firmware) is sent in parallel but is unreliable on some straps — the Device-tab
// test uses RUN_HAPTICS + RUN_ALARM immediately, which is a different code path. This scheduler
// bridges that gap while the app process is alive (foreground or brief background).

@MainActor
final class StrapAlarmScheduler {
    static let shared = StrapAlarmScheduler()

    private var fireItem: DispatchWorkItem?

    private init() {}

    /// Schedule `onFire` at `fireDate`. No-op when the time is already past.
    func schedule(at fireDate: Date, onFire: @escaping () -> Void) {
        cancel()
        let delay = fireDate.timeIntervalSinceNow
        guard delay > 0 else { return }
        let item = DispatchWorkItem(block: onFire)
        fireItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        fireItem?.cancel()
        fireItem = nil
    }
}
