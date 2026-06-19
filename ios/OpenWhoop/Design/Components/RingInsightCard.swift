import SwiftUI

// MARK: - RingInsightCard
// Párrafo interpretativo bajo el anillo hero en las pantallas de detalle.

struct RingInsightCard: View {
    let text: String

    var body: some View {
        DashboardCard {
            HStack(alignment: .top, spacing: WH.Spacing.sm) {
                Image(systemName: "text.quote")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WH.Color.strainBlue)
                    .padding(.top, 2)
                Text(text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(WH.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(WH.Spacing.md)
        }
    }
}
