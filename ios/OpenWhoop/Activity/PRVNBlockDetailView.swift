import SwiftUI

// MARK: - PRVNBlockDetailView
// Texto completo del bloque importado desde SugarWOD / PRVN.

struct PRVNBlockDetailView: View {
    let block: ProgramBlock
    var date: Date = Date()

    var body: some View {
        ZStack {
            WH.Color.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                    header
                    Text(block.body)
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .foregroundStyle(WH.Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(WH.Spacing.md)
            }
        }
        .navigationTitle(block.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            HStack(spacing: WH.Spacing.sm) {
                Image(systemName: block.kind.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WH.Color.strainBlue)
                Text(block.kind.displayName.uppercased())
                    .font(WH.Font.cardTitle)
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.2)
            }
            if let title = block.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
            }
            Text(dayLabel)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private var dayLabel: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return fmt.string(from: date).capitalized
    }
}
