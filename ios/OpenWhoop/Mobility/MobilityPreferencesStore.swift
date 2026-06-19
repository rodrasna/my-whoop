import Foundation
import Combine

// MARK: - MobilityPreferencesStore

@MainActor
final class MobilityPreferencesStore: ObservableObject {
    static let shared = MobilityPreferencesStore()

    private static let storageKey = "com.openwhoop.mobility.prefs.v1"

    @Published var focusAreas: Set<MobilityFocusArea> {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Set<MobilityFocusArea>.self, from: data),
           !decoded.isEmpty {
            focusAreas = decoded
        } else {
            focusAreas = [.hips, .shoulders, .thoracic]
        }
    }

    func toggle(_ area: MobilityFocusArea) {
        if focusAreas.contains(area) {
            if focusAreas.count > 1 { focusAreas.remove(area) }
        } else {
            focusAreas.insert(area)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(focusAreas) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
