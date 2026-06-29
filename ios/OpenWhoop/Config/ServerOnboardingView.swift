import SwiftUI

// MARK: - ServerOnboardingView
// Primera configuración: identificador único por usuario en servidor compartido.

struct ServerOnboardingView: View {
    @ObservedObject var settings: ServerConnectionSettings
    let onComplete: () -> Void

    @State private var deviceId: String = ""
    @State private var showAdvanced = false
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isTesting = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                    header
                    deviceIdField
                    if showAdvanced { advancedFields }
                    actions
                    if let successMessage {
                        Text(successMessage)
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.recoveryGreen)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.recoveryRed)
                    }
                }
                .padding(WH.Spacing.lg)
            }
            .background(WH.Color.background.ignoresSafeArea())
            .navigationTitle("Tu cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            deviceId = settings.suggestedDeviceId
            baseURL = settings.baseURLOverride
            apiKey = settings.apiKeyOverride
            if settings.baseURLOverride.isEmpty, let url = ServerConnectionSettings.buildBaseURL {
                baseURL = url.absoluteString
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("Identificador único")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            Text("El servidor es compartido. Tu identificador separa tu historial del de otras personas. Elige uno distinto (ej. tu nombre en minúsculas).")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deviceIdField: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            Text("Tu identificador")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
            TextField("ej. maria-whoop", text: $deviceId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .padding(WH.Spacing.sm)
                .background(WH.Color.surface,
                            in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
        }
    }

    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.md) {
            VStack(alignment: .leading, spacing: WH.Spacing.xs) {
                Text("URL del servidor (opcional)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary)
                TextField("https://whoop.tudominio.com", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(.caption, design: .monospaced))
                    .padding(WH.Spacing.sm)
                    .background(WH.Color.surface,
                                in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
            }
            VStack(alignment: .leading, spacing: WH.Spacing.xs) {
                Text("Clave API (opcional)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary)
                SecureField("Bearer token del servidor", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.caption, design: .monospaced))
                    .padding(WH.Spacing.sm)
                    .background(WH.Color.surface,
                                in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
            }
            Text("Si el build de TestFlight ya incluye servidor, deja estos campos vacíos.")
                .font(.system(size: 11))
                .foregroundStyle(WH.Color.textSecondary)
        }
    }

    private var actions: some View {
        VStack(spacing: WH.Spacing.sm) {
            Button {
                showAdvanced.toggle()
            } label: {
                Text(showAdvanced ? "Ocultar avanzado" : "Opciones avanzadas")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(WH.Color.strainBlue)

            Button {
                Task { await testConnection() }
            } label: {
                HStack {
                    if isTesting { ProgressView().tint(WH.Color.textPrimary) }
                    Text("Probar conexión")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isTesting || isSaving)

            Button {
                Task { await saveAndContinue() }
            } label: {
                HStack {
                    if isSaving { ProgressView().tint(WH.Color.background) }
                    Text("Continuar")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, WH.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(WH.Color.strainBlue)
            .disabled(isTesting || isSaving || deviceId.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func applyDraftToSettings() {
        settings.baseURLOverride = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.apiKeyOverride = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func testConnection() async {
        errorMessage = nil
        successMessage = nil
        isTesting = true
        applyDraftToSettings()
        let result = await settings.testConnection(deviceId: deviceId)
        isTesting = false
        switch result {
        case .success(let msg): successMessage = msg
        case .failure(let err): errorMessage = err.localizedDescription
        }
    }

    private func saveAndContinue() async {
        errorMessage = nil
        successMessage = nil
        isSaving = true
        applyDraftToSettings()
        do {
            try settings.completeOnboarding(deviceId: deviceId)
            isSaving = false
            onComplete()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}
