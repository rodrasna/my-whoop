import SwiftUI

// MARK: - DayNavigator
// Official-style day picker for the Today tab: calendar label with prev/next arrows.

struct DayNavigator: View {
    @Binding var selectedDate: Date
    var maxPastDays: Int = 30
    var showsCalendarPicker: Bool = false

    @State private var showingPicker = false

    private var canGoForward: Bool {
        !Calendar.current.isDateInToday(selectedDate)
    }

    private var canGoBack: Bool {
        guard let limit = Calendar.current.date(byAdding: .day, value: -maxPastDays, to: Date()) else {
            return false
        }
        return selectedDate > limit
    }

    private var label: String {
        if Calendar.current.isDateInToday(selectedDate) { return "Hoy" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Ayer" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return fmt.string(from: selectedDate)
    }

    private var pastLimit: Date {
        Calendar.current.date(byAdding: .day, value: -maxPastDays, to: Date()) ?? selectedDate
    }

    var body: some View {
        HStack(spacing: WH.Spacing.xs) {
            navButton(systemName: "chevron.left", enabled: canGoBack) {
                shift(-1)
            }

            Group {
                if showsCalendarPicker {
                    Button { showingPicker = true } label: { dayLabel }
                        .buttonStyle(.plain)
                } else {
                    dayLabel
                }
            }

            navButton(systemName: "chevron.right", enabled: canGoForward) {
                shift(1)
            }
        }
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                DatePicker(
                    "Día",
                    selection: $selectedDate,
                    in: pastLimit...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
                .navigationTitle("Elegir día")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") { showingPicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .preferredColorScheme(.dark)
        }
    }

    private var dayLabel: some View {
        HStack(spacing: WH.Spacing.xs) {
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
            Text(label)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func navButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? WH.Color.textPrimary : WH.Color.textSecondary.opacity(0.25))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func shift(_ days: Int) {
        let start = Calendar.current.startOfDay(for: selectedDate)
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: start) else { return }
        selectedDate = next
    }
}

// MARK: - StrapStatusButton
// Compact strap + battery (+ live BPM when connected). Tapping opens the Device console.

struct StrapStatusButton: View {
    @ObservedObject var state: LiveState
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if state.connected, let hr = state.heartRate {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WH.Color.recoveryRed)
                        Text("\(hr)")
                            .font(.system(size: 14, weight: .heavy, design: .default))
                            .fontWidth(.condensed)
                            .monospacedDigit()
                            .foregroundStyle(WH.Color.textPrimary)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: state.connected
                          ? "sensor.tag.radiowaves.forward.fill"
                          : "sensor.tag.radiowaves.forward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(state.connected ? WH.Color.strainBlue : WH.Color.textSecondary)

                    if let bat = state.batteryPct {
                        Text("\(Int(bat.rounded()))%")
                            .font(.system(size: 14, weight: .heavy, design: .default))
                            .fontWidth(.condensed)
                            .monospacedDigit()
                            .foregroundStyle(batteryColor(Int(bat.rounded())))
                    } else if !state.connected {
                        Text("—")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }
            }
            .padding(.horizontal, WH.Spacing.sm)
            .padding(.vertical, WH.Spacing.xs)
            .background(WH.Color.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.connected ? "Dispositivo conectado" : "Conectar dispositivo")
    }

    private func batteryColor(_ pct: Int) -> Color {
        if pct > 30 { return WH.Color.recoveryGreen }
        if pct > 15 { return WH.Color.recoveryYellow }
        return WH.Color.recoveryRed
    }
}

// MARK: - TodayTopBar
// Day navigator (leading) + strap status (trailing) — replaces the plain ScreenHeader on Today.

struct TodayTopBar: View {
    @Binding var selectedDate: Date
    @ObservedObject var liveState: LiveState
    var onDeviceTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: WH.Spacing.sm) {
            DayNavigator(selectedDate: $selectedDate)
            Spacer(minLength: WH.Spacing.xs)
            StrapStatusButton(state: liveState, action: onDeviceTap)
        }
        .padding(.top, WH.Spacing.sm)
        .padding(.bottom, WH.Spacing.xs)
    }
}
