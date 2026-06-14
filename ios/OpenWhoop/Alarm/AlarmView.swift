import SwiftUI

// MARK: - AlarmView
// Alarm configuration screen (M6).
// Presents: a wake-by time picker, a smart-wake toggle + lead-time stepper,
// an enable/disable toggle, and Set/Turn-off actions.
// Settings are persisted to UserDefaults (keys: AlarmKeys.*).
// On enable: computes next occurrence of the wake-by time and calls BLEManager.armStrapAlarm(at:).
// On disable: calls BLEManager.disableStrapAlarm().
//
// NOTE: Haptic/firmware firing cannot be verified in the simulator (no strap).
// The "Alarm set" status line and all UI controls are sim-verifiable.

// MARK: - UserDefaults keys

enum AlarmKeys {
    static let enabled          = "alarmEnabled"
    static let wakeByHour       = "alarmWakeByHour"
    static let wakeByMinute     = "alarmWakeByMinute"
    static let smartWakeEnabled = "alarmSmartWakeEnabled"
    static let smartWakeLeadMin = "alarmSmartWakeLeadMin"
    /// Epoch seconds of the last successfully armed firmware alarm, for the status line.
    static let armedEpoch       = "alarmArmedEpoch"
}

// MARK: - AlarmView

struct AlarmView: View {
    @Environment(\.dismiss) private var dismiss

    // The shared LiveViewModel (and its single BLEManager) is injected via the environment
    // from AppRoot → TodayView sheet → AlarmView. Alarm commands call through passthroughs
    // on LiveViewModel so AlarmView never needs a raw BLEManager reference.
    @EnvironmentObject var live: LiveViewModel

    // Persisted alarm settings
    @AppStorage(AlarmKeys.enabled)          private var alarmEnabled   = false
    @AppStorage(AlarmKeys.wakeByHour)       private var wakeByHour     = 7
    @AppStorage(AlarmKeys.wakeByMinute)     private var wakeByMinute   = 0
    @AppStorage(AlarmKeys.smartWakeEnabled) private var smartWakeEnabled = false
    @AppStorage(AlarmKeys.smartWakeLeadMin) private var smartWakeLeadMin = 20
    @AppStorage(AlarmKeys.armedEpoch)       private var armedEpoch: Double = 0

    // Transient state for the DatePicker binding
    @State private var wakeByDate: Date = AlarmView.todayAt(hour: 7, minute: 0)
    /// Controla la alerta de pulsera desconectada.
    @State private var showDisconnectedAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                Form {
                    alarmTimeSection
                    smartWakeSection
                    enableSection
                    statusSection
                    notesSection
                }
                .scrollContentBackground(.hidden)
                .background(WH.Color.background)
            }
            .navigationTitle("Alarma")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(WH.Color.strainBlue)
                }
            }
            .onAppear { syncPickerFromStorage() }
            .onChange(of: wakeByDate) { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                wakeByHour   = comps.hour   ?? wakeByHour
                wakeByMinute = comps.minute ?? wakeByMinute
            }
            .alert("Pulsera no conectada", isPresented: $showDisconnectedAlert) {
                Button("Armar de todos modos", role: .destructive) { setAlarm() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("La alarma se programa en la pulsera y no sonará si no la conectas antes de armarla.")
            }
        }
    }

    // MARK: - Sections

    private var alarmTimeSection: some View {
        Section {
            DatePicker(
                "Despertar antes de",
                selection: $wakeByDate,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .tint(WH.Color.strainBlue)
            .foregroundStyle(WH.Color.textPrimary)
            .listRowBackground(WH.Color.surface)
        } header: {
            sectionHeader("Hora límite")
        }
    }

    private var smartWakeSection: some View {
        Section {
            Toggle("Despertar inteligente", isOn: $smartWakeEnabled)
                .tint(WH.Color.sleepPurple)
                .foregroundStyle(WH.Color.textPrimary)
                .listRowBackground(WH.Color.surface)

            if smartWakeEnabled {
                Stepper(
                    "Hasta \(smartWakeLeadMin) min antes",
                    value: $smartWakeLeadMin,
                    in: 5...30,
                    step: 5
                )
                .foregroundStyle(WH.Color.textPrimary)
                .listRowBackground(WH.Color.surface)
            }
        } header: {
            sectionHeader("Despertar inteligente")
        } footer: {
            Text("El despertar inteligente analiza tu FC y movimiento para encontrar un momento de sueño ligero "
                 + "dentro de la ventana configurada y activa la vibración en el momento óptimo. "
                 + "Requiere llevar la pulsera puesta y conectada. "
                 + "La alarma a hora fija siempre se activa como red de seguridad.")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
    }

    private var enableSection: some View {
        Section {
            HStack(spacing: WH.Spacing.sm) {
                Button {
                    armAlarmOrWarn()
                } label: {
                    Label("Programar alarma", systemImage: "alarm")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WH.Spacing.xs)
                }
                .buttonStyle(.borderedProminent)
                .tint(WH.Color.strainBlue)

                Button(role: .destructive) {
                    disableAlarm()
                } label: {
                    Label("Desactivar", systemImage: "alarm.slash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WH.Spacing.xs)
                }
                .buttonStyle(.bordered)
                .tint(WH.Color.recoveryRed)
            }
            .listRowBackground(WH.Color.surface)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: WH.Spacing.xs) {
                if alarmEnabled, armedEpoch > 0 {
                    let fireDate = Date(timeIntervalSince1970: armedEpoch)
                    HStack(spacing: WH.Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(WH.Color.recoveryGreen)
                            .font(.system(size: 14))
                        Text("Alarma programada para las \(formattedTime(fireDate))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(WH.Color.textPrimary)
                    }
                    Text("La pulsera vibrará a las \(formattedTime(fireDate)).")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                    if smartWakeEnabled {
                        Text("Despertar inteligente: buscará un momento de sueño ligero hasta "
                             + "\(smartWakeLeadMin) min antes.")
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                } else {
                    HStack(spacing: WH.Spacing.xs) {
                        Image(systemName: "alarm.slash")
                            .foregroundStyle(WH.Color.textSecondary)
                            .font(.system(size: 14))
                        Text("Sin alarma programada")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }
            }
            .padding(.vertical, WH.Spacing.xs)
            .listRowBackground(WH.Color.surface)
        } header: {
            sectionHeader("Estado")
        }
    }

    private var notesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: WH.Spacing.sm) {
                noteRow(icon: "wave.3.right",
                        text: "La pulsera debe estar conectada y puesta en el momento de armar para que la alarma suene.")
                noteRow(icon: "iphone.slash",
                        text: "La alarma de firmware a hora fija se activa aunque la app esté cerrada o el móvil bloqueado.")
                noteRow(icon: "exclamationmark.triangle",
                        text: "El despertar inteligente por BLE en segundo plano requiere prueba en dispositivo real — "
                            + "no puede verificarse en el simulador.")
            }
            .padding(.vertical, WH.Spacing.xs)
            .listRowBackground(WH.Color.surface)
        } header: {
            sectionHeader("Notas")
        }
    }

    // MARK: - Row helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(WH.Font.cardTitle)
            .foregroundStyle(WH.Color.textSecondary)
            .tracking(1.2)
    }

    private func noteRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: WH.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WH.Color.textSecondary.opacity(0.7))
                .frame(width: 16)
            Text(text)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    /// Comprueba si la pulsera está conectada antes de armar.
    /// Si no lo está, muestra una alerta de advertencia; si sí, arma directamente.
    private func armAlarmOrWarn() {
        if live.state.connected {
            setAlarm()
        } else {
            showDisconnectedAlert = true
        }
    }

    private func setAlarm() {
        let fireDate = nextOccurrence(hour: wakeByHour, minute: wakeByMinute)
        alarmEnabled = true
        armedEpoch   = fireDate.timeIntervalSince1970
        // armStrapAlarm returns the shared BLEManager so SmartAlarmController can hold it weakly.
        let ble = live.armStrapAlarm(at: fireDate)
        // Wire up smart-wake if enabled (SmartAlarmController arms itself in the window)
        if smartWakeEnabled {
            SmartAlarmController.shared.schedule(
                wakeBy: fireDate,
                leadMinutes: smartWakeLeadMin,
                ble: ble
            )
        }
    }

    private func disableAlarm() {
        alarmEnabled = false
        armedEpoch   = 0
        live.disableStrapAlarm()
        SmartAlarmController.shared.cancel()
    }

    // MARK: - Helpers

    private func syncPickerFromStorage() {
        wakeByDate = AlarmView.todayAt(hour: wakeByHour, minute: wakeByMinute)
    }

    /// Returns a `Date` for today at `hour:minute` (local time).
    static func todayAt(hour: Int, minute: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour   = hour
        comps.minute = minute
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    /// Next occurrence of `hour:minute` — today if still in the future, tomorrow otherwise.
    private func nextOccurrence(hour: Int, minute: Int) -> Date {
        let candidate = AlarmView.todayAt(hour: hour, minute: minute)
        if candidate > Date() { return candidate }
        return Calendar.current.date(byAdding: .day, value: 1, to: candidate) ?? candidate
    }

    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle  = .short
        f.timeStyle  = .short
        return f.string(from: date)
    }
}

// MARK: - Preview

#Preview("Alarm — no alarm set") {
    AlarmView()
        .environmentObject(LiveViewModel())
}
