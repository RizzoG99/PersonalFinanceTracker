import SwiftUI

struct HealthScoreSection: View {
    let healthScore: HealthScore?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InsightsSectionHeader(title: "Health Score", subtitle: "How your finances are doing")
            if let score = healthScore {
                HealthScoreCard(healthScore: score)
            }
        }
    }
}
