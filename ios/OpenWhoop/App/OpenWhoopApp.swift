import SwiftUI

@main
struct OpenWhoopApp: App {
    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }
}

/// Gates onboarding, then mounts the main tab shell with env objects.
private struct AppRoot: View {
    @StateObject private var serverSettings = ServerConnectionSettings.shared
    @State private var showMainApp = false

    var body: some View {
        Group {
            if serverSettings.needsOnboarding && !showMainApp {
                ServerOnboardingView(settings: serverSettings) {
                    showMainApp = true
                }
            } else {
                MainAppShell()
            }
        }
    }
}

/// Tab shell + BLE/metrics env objects. Created after onboarding so device_id is final.
private struct MainAppShell: View {
    @StateObject private var serverSettings = ServerConnectionSettings.shared
    @StateObject private var metrics: MetricsRepository
    @StateObject private var live: LiveViewModel
    @StateObject private var tabRouter = RootTabRouter()
    @ObservedObject private var dayPlanStore = WorkoutDayPlanStore.shared

    init() {
        let settings = ServerConnectionSettings.shared
        let deviceId = settings.effectiveDeviceId.isEmpty ? "my-whoop" : settings.effectiveDeviceId
        _metrics = StateObject(wrappedValue: MetricsRepository(settings: settings))
        _live = StateObject(wrappedValue: LiveViewModel(deviceId: deviceId))
    }

    var body: some View {
        RootTabView()
            .environmentObject(metrics)
            .environmentObject(live)
            .environmentObject(tabRouter)
            .environmentObject(serverSettings)
            .environmentObject(dayPlanStore)
            .task {
                if ProcessInfo.processInfo.arguments.contains("-demoPreview") {
                    await metrics.loadDemoPreview()
                } else {
                    await metrics.syncPRVNProgramIfSunday()
                }
                SleepCheckInNotifier.requestAuthorization()
                SleepCheckInNotifier.reschedule()
            }
    }
}
