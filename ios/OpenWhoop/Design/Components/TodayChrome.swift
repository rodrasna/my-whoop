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

    private struct StrapStatusVisual {
        let symbol: String
        let color: Color
        let label: String
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                let status = strapStatusVisual()

                Image(systemName: status.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(status.color)

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
        .accessibilityLabel(accessibilityLabel)
    }

    private func batteryColor(_ pct: Int) -> Color {
        if pct > 30 { return WH.Color.recoveryGreen }
        if pct > 15 { return WH.Color.recoveryYellow }
        return WH.Color.recoveryRed
    }

    private var accessibilityLabel: String {
        let status = strapStatusVisual().label
        let hr = state.heartRate.map { "\($0) pulsaciones" } ?? "sin frecuencia cardiaca"
        let battery = state.batteryPct.map { "batería \(Int($0.rounded())) por ciento" } ?? "batería desconocida"
        return "\(status), \(hr), \(battery)"
    }

    private func strapStatusVisual() -> StrapStatusVisual {
        if state.repairStatus != nil {
            return StrapStatusVisual(
                symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                color: WH.Color.recoveryYellow,
                label: "Reparando reloj"
            )
        }
        if state.clockLossStatus != nil {
            return StrapStatusVisual(
                symbol: "clock.arrow.circlepath",
                color: WH.Color.recoveryYellow,
                label: "Reloj perdido"
            )
        }
        if state.offloadStalled || state.strapNeedsReboot {
            return StrapStatusVisual(
                symbol: "exclamationmark.triangle.fill",
                color: WH.Color.recoveryYellow,
                label: state.offloadStalled
                    ? "Descarga sin progreso"
                    : "Pulsera atascada o desincronizada"
            )
        }
        if state.isOffloading {
            return StrapStatusVisual(
                symbol: "arrow.trianglehead.2.clockwise.rotate.90",
                color: WH.Color.recoveryYellow,
                label: "Sincronizando historial"
            )
        }
        if state.connected && state.bonded {
            let now = Date().timeIntervalSince1970
            switch StalenessPolicy.state(lastSyncedAt: state.lastSyncedAt, now: now) {
            case .caughtUp:
                return StrapStatusVisual(
                    symbol: "checkmark.circle.fill",
                    color: WH.Color.recoveryGreen,
                    label: "Sincronizado"
                )
            case .catchingUp:
                return StrapStatusVisual(
                    symbol: "arrow.trianglehead.2.clockwise.rotate.90",
                    color: WH.Color.recoveryYellow,
                    label: "Poniéndose al día"
                )
            case .stale:
                return StrapStatusVisual(
                    symbol: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                    color: WH.Color.recoveryRed,
                    label: "Desincronizado"
                )
            case .neverSynced:
                return StrapStatusVisual(
                    symbol: "arrow.clockwise.circle.fill",
                    color: WH.Color.textSecondary,
                    label: "Sin sincronizar"
                )
            }
        }
        if state.connected {
            return StrapStatusVisual(
                symbol: "dot.radiowaves.left.and.right",
                color: WH.Color.strainBlue,
                label: "Conectado"
            )
        }
        return StrapStatusVisual(
            symbol: "wifi.slash",
            color: WH.Color.textSecondary,
            label: "Desconectado"
        )
    }
}

// MARK: - StallRecoveryBanner
// Shown after 3 incomplete offload timeouts — auto-sync pauses; user can repair or retry once.

struct StallRecoveryBanner: View {
    var timeoutCount: Int
    /// True when stall is driven by CLOCK-LOST / corrupt DATA_RANGE (not a generic BLE jam).
    var isClockLoss: Bool = false
    var onRepair: () -> Void
    var onRetrySync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            HStack(spacing: WH.Spacing.xs) {
                Image(systemName: isClockLoss
                      ? "clock.arrow.circlepath"
                      : "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WH.Color.recoveryYellow)
                Text(isClockLoss
                     ? OffloadStallPolicy.clockHoldBannerTitle
                     : "Descarga atascada")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WH.Color.textPrimary)
            }
            Text(
                isClockLoss
                ? OffloadStallPolicy.clockHoldBannerBody
                : (timeoutCount >= 3
                   ? "La pulsera no terminó la descarga tras \(timeoutCount) intentos. "
                     + "Repara el reloj (reinicia la pulsera) o ponla en el cargador ~30–60 s."
                   : "La descarga no avanza. Repara el reloj o reintenta cuando la pulsera esté en la muñeca.")
            )
            .font(WH.Font.caption)
            .foregroundStyle(WH.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: WH.Spacing.sm) {
                Button(action: onRepair) {
                    Label("Reparar pulsera", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WH.Spacing.sm)
                        .background(WH.Color.recoveryRed.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(WH.Color.recoveryRed)

                Button(action: onRetrySync) {
                    Label("Reintentar", systemImage: "arrow.trianglehead.2.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WH.Spacing.sm)
                        .background(WH.Color.teal.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(WH.Color.teal)
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.recoveryYellow.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous)
                .strokeBorder(WH.Color.recoveryYellow.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - TodayTopBar
// Day navigator (leading) + strap status (trailing) — replaces the plain ScreenHeader on Today.

struct TodayTopBar: View {
    @Binding var selectedDate: Date
    @ObservedObject var liveState: LiveState
    /// When false, shows a fixed title (no chevron day paging).
    var showsDayNavigation: Bool = true
    var fixedTitle: String = "Hoy"
    var onDeviceTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: WH.Spacing.sm) {
            if showsDayNavigation {
                DayNavigator(selectedDate: $selectedDate)
            } else {
                Text(fixedTitle)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
            }
            Spacer(minLength: WH.Spacing.xs)
            StrapStatusButton(state: liveState, action: onDeviceTap)
        }
        .padding(.top, WH.Spacing.sm)
        .padding(.bottom, WH.Spacing.xs)
    }
}
