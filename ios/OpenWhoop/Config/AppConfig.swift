import Foundation

/// Server upload configuration, read from build defaults + per-install overrides.
public struct UploaderConfig: Equatable {
    public let baseURL: URL
    public let apiKey: String
    public init(baseURL: URL, apiKey: String) { self.baseURL = baseURL; self.apiKey = apiKey }
}

enum AppConfig {
    /// Returns nil when unconfigured (missing/placeholder), so the app simply doesn't upload.
    @MainActor
    static func uploaderConfig() -> UploaderConfig? {
        ServerConnectionSettings.shared.uploaderConfig()
    }

    /// Legacy helper — prefers ServerConnectionSettings, then build default.
    @MainActor
    static func deviceId() -> String {
        let effective = ServerConnectionSettings.shared.effectiveDeviceId
        if !effective.isEmpty { return effective }
        return buildDeviceIdFromPlist() ?? "my-whoop"
    }

    private static func buildDeviceIdFromPlist() -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: "WHOOP_DEVICE_ID") as? String,
              !v.isEmpty, v != "$(WHOOP_DEVICE_ID)" else { return nil }
        return v
    }
}
