import Foundation
import Combine

// MARK: - RootTabRouter
// Navegación entre pestañas y deep links (p. ej. Actividad → Movilidad con sesión concreta).

@MainActor
final class RootTabRouter: ObservableObject {

    enum Tab: Int {
        case today = 0
        case sleep = 1
        case health = 2
        case activity = 3
        case mobility = 4
    }

    @Published var selectedTab: Int
    @Published private(set) var pendingMobilitySession: MobilitySessionKind?

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-startTab"), i + 1 < args.count,
           let n = Int(args[i + 1]) {
            selectedTab = n
        } else {
            selectedTab = Tab.today.rawValue
        }
        if let i = args.firstIndex(of: "-mobilitySession"), i + 1 < args.count {
            pendingMobilitySession = MobilitySessionKind(rawValue: args[i + 1])
        }
    }

    func openMobility(_ session: MobilitySessionKind) {
        pendingMobilitySession = session
        selectedTab = Tab.mobility.rawValue
    }

    /// Aplica y limpia la sesión pendiente (una sola vez).
    func consumeMobilitySession() -> MobilitySessionKind? {
        defer { pendingMobilitySession = nil }
        return pendingMobilitySession
    }
}
