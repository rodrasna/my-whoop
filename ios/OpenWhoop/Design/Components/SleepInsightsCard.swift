import SwiftUI

// MARK: - SleepInsightsCard
// Patrones personales del cuestionario matutino + métricas de pulsera.

struct SleepInsightsPayload: Equatable {
    let ready: Bool
    let checkInCount: Int
    let minRequired: Int
    let message: String?
    let topInsight: String?
    let insights: [SleepInsightItem]

    struct SleepInsightItem: Equatable, Identifiable {
        let id: String
        let kind: String
        let text: String
    }
}

struct SleepInsightsCard: View {
    @EnvironmentObject private var metrics: MetricsRepository

    var body: some View {
        if let payload = metrics.sleepInsights {
            VStack(alignment: .leading, spacing: WH.Spacing.sm) {
                header(count: payload.checkInCount)
                if payload.ready, let top = payload.topInsight {
                    Text(top)
                        .font(.system(size: 14))
                        .foregroundStyle(WH.Color.textPrimary)
                    ForEach(payload.insights.filter { $0.kind == "factor" }.prefix(2)) { item in
                        Text("· \(item.text)")
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                } else {
                    Text(payload.message ?? "Responde 7 mañanas para ver patrones personales.")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }
            .padding(WH.Spacing.md)
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
    }

    private func header(count: Int) -> some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(WH.Color.sleepPurple)
            Text("TUS PATRONES DE SUEÑO")
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)
            Spacer()
            Text("\(count)d")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(WH.Color.textSecondary)
        }
    }
}
