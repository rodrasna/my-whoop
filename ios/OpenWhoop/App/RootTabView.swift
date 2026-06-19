import SwiftUI
import UIKit

struct RootTabView: View {
    @EnvironmentObject private var tabRouter: RootTabRouter

    init() {
        Self.configureTabBarAppearance()
    }

    var body: some View {
        TabView(selection: $tabRouter.selectedTab) {
            TodayView()
                .tabItem {
                    Label("Hoy", systemImage: "house.fill")
                }
                .tag(RootTabRouter.Tab.today.rawValue)

            SleepView()
                .tabItem {
                    Label("Sueño", systemImage: "moon.stars.fill")
                }
                .tag(RootTabRouter.Tab.sleep.rawValue)

            HealthView()
                .tabItem {
                    Label("Salud", systemImage: "heart.text.square.fill")
                }
                .tag(RootTabRouter.Tab.health.rawValue)

            WorkoutsView()
                .tabItem {
                    Label("Actividad", systemImage: "bolt.fill")
                }
                .tag(RootTabRouter.Tab.activity.rawValue)

            MobilityView()
                .tabItem {
                    Label("Movilidad", systemImage: "figure.flexibility")
                }
                .tag(RootTabRouter.Tab.mobility.rawValue)
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
