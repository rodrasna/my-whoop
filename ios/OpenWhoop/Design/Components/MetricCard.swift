import SwiftUI

// MARK: - MetricCard
// Dark rounded card displaying a titled metric.
// Flexible: title + big value + optional unit + optional accessory view.
// Used for Recovery %, Strain, Sleep hours, HRV, RHR, SpO2, etc.

struct MetricCard<Accessory: View>: View {

    var title: String
    var value: String
    var unit: String?
    var accentColor: Color = WH.Color.textPrimary
    var accessory: (() -> Accessory)?

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {

            // --- Header row ---
            HStack {
                Text(title.uppercased())
                    .font(WH.Font.cardTitle)
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.2)
                Spacer()
            }

            // --- Value + unit ---
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(WH.Font.metricMedium())
                    .foregroundStyle(accentColor)
                    .monospacedDigit()

                if let unit {
                    Text(unit)
                        .font(WH.Font.unit)
                        .foregroundStyle(WH.Color.textSecondary)
                }

                Spacer(minLength: 0)
            }

            // --- Optional accessory (e.g. sparkline, dot, badge) ---
            if let accessory {
                accessory()
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface, in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }
}

// Convenience init without accessory
extension MetricCard where Accessory == EmptyView {
    init(title: String, value: String, unit: String? = nil, accentColor: Color = WH.Color.textPrimary) {
        self.title = title
        self.value = value
        self.unit = unit
        self.accentColor = accentColor
        self.accessory = nil
    }
}

// MARK: - DashboardRow
// Full-width metric row mirroring the official app's "dashboard" list:
// leading SF Symbol + uppercase label, trailing big value with an optional
// baseline (30-day typical) underneath. Used by the Today dashboard section.

struct DashboardRow: View {

    /// Direction of the current value vs its 30-day baseline (official-style indicator).
    enum Trend { case up, down, flat }

    var icon: String
    var label: String
    var value: String
    var unit: String? = nil
    /// Small secondary number under the value (e.g. 30-day baseline).
    var baseline: String? = nil
    var accentColor: Color = WH.Color.textPrimary
    /// When true, row has no card background (for use inside DashboardCard).
    var embedded: Bool = false
    /// Optional up/down/flat marker shown after the value.
    var trend: Trend? = nil

    var body: some View {
        HStack(spacing: WH.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
                .frame(width: 24)

            Text(label.uppercased())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WH.Color.textPrimary)
                .tracking(0.8)
                .lineLimit(2)

            Spacer(minLength: WH.Spacing.sm)

            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 26, weight: .bold, design: .default))
                        .fontWidth(.condensed)
                        .foregroundStyle(accentColor)
                        .monospacedDigit()
                    if let unit {
                        Text(unit)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                    if let trend {
                        Image(systemName: trend == .up ? "arrowtriangle.up.fill"
                                        : trend == .down ? "arrowtriangle.down.fill"
                                        : "circle.fill")
                            .font(.system(size: trend == .flat ? 5 : 9, weight: .bold))
                            .foregroundStyle(WH.Color.textSecondary)
                            .padding(.leading, 1)
                    }
                }
                if let baseline {
                    Text(baseline)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .fontWidth(.condensed)
                        .foregroundStyle(WH.Color.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, WH.Spacing.md)
        .padding(.vertical, WH.Spacing.md)
        .background {
            if !embedded {
                WH.Color.surface
                    .clipShape(RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            }
        }
    }
}

// MARK: - Preview

#Preview("Dashboard rows") {
    VStack(spacing: WH.Spacing.sm) {
        DashboardRow(icon: "waveform.path.ecg", label: "Heart Rate Variability",
                     value: "62", unit: "ms", baseline: "58", accentColor: WH.Color.recoveryGreen)
        DashboardRow(icon: "heart", label: "Resting Heart Rate",
                     value: "48", unit: "bpm", baseline: "50")
        DashboardRow(icon: "flame", label: "Calories", value: "692", baseline: "459")
    }
    .padding(WH.Spacing.md)
    .background(WH.Color.background)
}

#Preview("Metric Cards") {
    VStack(spacing: WH.Spacing.sm) {
        MetricCard(title: "Strain", value: "14.2", accentColor: WH.Color.strainBlue)
        MetricCard(title: "Sleep", value: "7h 23m", accentColor: WH.Color.textPrimary)
        MetricCard(title: "HRV", value: "62", unit: "ms", accentColor: WH.Color.recoveryGreen)
        MetricCard(title: "Resting HR", value: "48", unit: "bpm")
        MetricCard(title: "SpO2", value: "97", unit: "%")
    }
    .padding(WH.Spacing.md)
    .background(WH.Color.background)
}
