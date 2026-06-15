import SwiftUI

// MARK: - CalibrationBanner
// Banner morado segmentado estilo WHOOP: "Usa X noches más para calibrar".

struct CalibrationBanner: View {

    var completedNights: Int
    var requiredNights: Int = 4
    var title: String = "Calibrando tu recuperación"
    var footnote: String? = nil

    private var remaining: Int { max(0, requiredNights - completedNights) }
    private var progress: Double {
        guard requiredNights > 0 else { return 0 }
        return min(1, Double(completedNights) / Double(requiredNights))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)

            HStack(spacing: 4) {
                ForEach(0..<requiredNights, id: \.self) { i in
                    Capsule()
                        .fill(i < completedNights ? WH.Color.calibrationAccent : WH.Color.ringTrack)
                        .frame(height: 6)
                }
            }

            Text(footnote ?? "Usa OpenWhoop \(remaining) noche\(remaining == 1 ? "" : "s") más para calibrar")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(WH.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WH.Color.calibrationBg,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous)
                .stroke(WH.Color.calibrationAccent.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(Int(progress * 100)) por ciento calibrado.")
    }
}

#Preview {
    VStack(spacing: WH.Spacing.md) {
        CalibrationBanner(completedNights: 1)
        CalibrationBanner(completedNights: 3, title: "Calibrando el sueño")
    }
    .padding()
    .background(WH.Color.background)
}
