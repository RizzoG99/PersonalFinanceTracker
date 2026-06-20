import SwiftUI

struct CategoryTrendsSection: View {
    let trends: [CategoryTrend]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Category Trends")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Text("vs last month")
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
            if trends.isEmpty {
                InsightsEmptyCard(message: "No expense data yet")
            } else {
                VStack(spacing: 8) {
                    ForEach(trends) { trend in
                        CategoryTrendRow(trend: trend)
                    }
                }
            }
        }
    }
}
