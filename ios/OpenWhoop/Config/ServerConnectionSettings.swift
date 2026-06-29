import Foundation
import Security

// MARK: - ServerConnectionSettings
// URL/API key por defecto vienen del build (Secrets.xcconfig). Cada instalación
// elige un device_id único para aislar datos en el servidor compartido.

@MainActor
final class ServerConnectionSettings: ObservableObject {
    static let shared = ServerConnectionSettings()

    @Published private(set) var userDeviceId: String
    @Published var baseURLOverride: String
    @Published var apiKeyOverride: String
    @Published private(set) var hasCompletedOnboarding: Bool

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let deviceId = "com.openwhoop.server.deviceId"
        static let baseURL = "com.openwhoop.server.baseURLOverride"
        static let onboardingComplete = "com.openwhoop.server.onboardingComplete"
        static let keychainAccount = "com.openwhoop.server.apiKey"
    }

    private init() {
        userDeviceId = defaults.string(forKey: Keys.deviceId) ?? ""
        baseURLOverride = defaults.string(forKey: Keys.baseURL) ?? ""
        apiKeyOverride = Self.readKeychain(account: Keys.keychainAccount) ?? ""
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboardingComplete)
    }

    var needsOnboarding: Bool { !hasCompletedOnboarding }

    /// Identificador efectivo para sync local + servidor.
    var effectiveDeviceId: String {
        let user = userDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty { return user }
        return Self.buildDeviceId ?? ""
    }

    var effectiveBaseURL: URL? {
        if let url = Self.normalizedURL(from: baseURLOverride) { return url }
        return Self.buildBaseURL
    }

    var effectiveAPIKey: String? {
        let override = apiKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return override }
        return Self.buildAPIKey
    }

    var isServerConfigured: Bool { uploaderConfig() != nil }

    var suggestedDeviceId: String {
        let user = userDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty { return user }
        return Self.buildDeviceId ?? ""
    }

    func uploaderConfig() -> UploaderConfig? {
        guard
            let url = effectiveBaseURL,
            let key = effectiveAPIKey,
            !key.isEmpty,
            key != "replace-me",
            url.absoluteString != "https://whoop.example.com"
        else { return nil }
        return UploaderConfig(baseURL: url, apiKey: key)
    }

    func completeOnboarding(deviceId: String) throws {
        let trimmed = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidDeviceId(trimmed) else {
            throw ValidationError.invalidDeviceId
        }
        userDeviceId = trimmed
        defaults.set(trimmed, forKey: Keys.deviceId)
        persistOverrides()
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Keys.onboardingComplete)
    }

    func saveAdvancedSettings() throws {
        let url = baseURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty, Self.normalizedURL(from: url) == nil {
            throw ValidationError.invalidURL
        }
        let id = userDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty, !Self.isValidDeviceId(id) {
            throw ValidationError.invalidDeviceId
        }
        persistOverrides()
    }

    func updateDeviceId(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidDeviceId(trimmed) else {
            throw ValidationError.invalidDeviceId
        }
        userDeviceId = trimmed
        defaults.set(trimmed, forKey: Keys.deviceId)
    }

    func testConnection(deviceId: String? = nil) async -> Result<String, Error> {
        guard let cfg = uploaderConfig() else {
            return .failure(ValidationError.serverNotConfigured)
        }
        let trimmedOverride = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: String? = {
            if let t = trimmedOverride, !t.isEmpty { return t }
            let effective = effectiveDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
            return effective.isEmpty ? nil : effective
        }()
        guard let id, Self.isValidDeviceId(id) else {
            return .failure(ValidationError.invalidDeviceId)
        }

        var request = URLRequest(url: cfg.baseURL.appendingPathComponent("healthz"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failure(ValidationError.healthCheckFailed)
            }
            if let body = String(data: data, encoding: .utf8), body.contains("ok") {
                return .success("Servidor OK · identificador «\(id)»")
            }
            return .success("Servidor respondió (\(id))")
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Build defaults (Info.plist / Secrets.xcconfig)

    static var buildBaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "WHOOP_BASE_URL") as? String else {
            return nil
        }
        return normalizedURL(from: raw)
    }

    static var buildAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "WHOOP_API_KEY") as? String,
              !key.isEmpty,
              key != "$(WHOOP_API_KEY)",
              key != "replace-me" else { return nil }
        return key
    }

    static var buildDeviceId: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "WHOOP_DEVICE_ID") as? String,
              !id.isEmpty,
              id != "$(WHOOP_DEVICE_ID)" else { return nil }
        return id
    }

    static func isValidDeviceId(_ value: String) -> Bool {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2, t.count <= 40 else { return false }
        return t.range(
            of: #"^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"#,
            options: .regularExpression
        ) != nil
    }

    private func persistOverrides() {
        let url = baseURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            defaults.removeObject(forKey: Keys.baseURL)
        } else {
            defaults.set(url, forKey: Keys.baseURL)
        }

        let key = apiKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            Self.deleteKeychain(account: Keys.keychainAccount)
        } else {
            Self.writeKeychain(account: Keys.keychainAccount, value: key)
        }

        let id = userDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            defaults.removeObject(forKey: Keys.deviceId)
        } else {
            defaults.set(id, forKey: Keys.deviceId)
        }
    }

    private static func normalizedURL(from raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        s = s.replacingOccurrences(of: "/$()", with: "//")
        if s.hasPrefix("https:/"), !s.hasPrefix("https://") {
            s = "https://" + s.dropFirst("https:/".count)
        }
        if s.hasPrefix("http:/"), !s.hasPrefix("http://") {
            s = "http://" + s.dropFirst("http:/".count)
        }
        guard let url = URL(string: s), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    // MARK: - Keychain

    private static func writeKeychain(account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "com.openwhoop.server",
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "com.openwhoop.server",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private static func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "com.openwhoop.server",
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum ValidationError: LocalizedError {
        case invalidDeviceId
        case invalidURL
        case serverNotConfigured
        case healthCheckFailed

        var errorDescription: String? {
            switch self {
            case .invalidDeviceId:
                return "Identificador inválido. Usa 2–40 caracteres: minúsculas, números y guiones."
            case .invalidURL:
                return "URL del servidor no válida."
            case .serverNotConfigured:
                return "Servidor no configurado. Revisa URL y clave API."
            case .healthCheckFailed:
                return "El servidor no respondió correctamente. Revisa URL, clave y red."
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
