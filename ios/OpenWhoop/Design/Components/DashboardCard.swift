import SwiftUI

// MARK: - DashboardCard
// Agrupa filas estilo WHOOP en una sola tarjeta con divisores.

struct DashboardCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }
}

struct DashboardDivider: View {
    var body: some View {
        Rectangle()
            .fill(WH.Color.separator.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }
}
