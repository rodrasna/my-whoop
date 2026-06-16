import SwiftUI
import UIKit

struct RootTabView: View {
    @State private var selection: Int = {
        // Screenshot helper: -startTab <0..3> picks the initial tab (simulator captures only).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-startTab"), i + 1 < args.count,
           let n = Int(args[i + 1]) { return n }
        return 0
    }()

    init() {
        Self.configureTabBarAppearance()
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem {
                    Label("Hoy", systemImage: "house.fill")
                }
                .tag(0)

            SleepView()
                .tabItem {
                    Label("Sueño", systemImage: "moon.stars.fill")
                }
                .tag(1)

            HealthView()
                .tabItem {
                    Label("Salud", systemImage: "heart.text.square.fill")
                }
                .tag(2)

            WorkoutsView()
                .tabItem {
                    Label("Actividad", systemImage: "bolt.fill")
                }
                .tag(3)
        }
        .tint(WH.Color.strainBlue)
    }

    /// True-black tab bar with a faint top hairline and accent-tinted selection,
    /// matching the official app's bottom navigation feel.
    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(WH.Color.background)
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.08)

        let accent = UIColor(WH.Color.strainBlue)
        let normal = UIColor(WH.Color.textSecondary)

        for item in [appearance.stackedLayoutAppearance,
                     appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            item.selected.iconColor = accent
            item.selected.titleTextAttributes = [
                .foregroundColor: accent,
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
            ]
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [
                .foregroundColor: normal,
                .font: UIFont.systemFont(ofSize: 10, weight: .medium)
            ]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
