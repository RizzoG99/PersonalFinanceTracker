import SwiftUI

struct HealthScoreCard: View {
    let healthScore: HealthScore
    let snapshots: [HealthScoreSnapshot]
    let onTap: () -> Void

    private var scoreColor: Color {
        switch healthScore.score {
        case 80...100: .positive
        case 60...79:  .accentIndigo
        case 40...59:  .categoryAmber
        default:       .negative
        }
    }

    var body: some View {
        Button(action: onTap) {
            GlassCard {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 20) {
                        ArcGaugeView(score: healthScore.score, scoreColor: scoreColor)
                            .frame(width: 100, height: 100)

                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(healthScore.score) / 100")
                                    .font(.title2.bold())
                                    .foregroundStyle(.textPrimary)
                                Text(healthScore.label)
                                    .font(.caption)
                                    .foregroundStyle(.textMid)
                            }

                            Divider()
                                .overlay { Color.white.opacity(0.1) }

                            ForEach(healthScore.components) { component in
                                ScoreComponentRow(component: component, scoreColor: scoreColor)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
