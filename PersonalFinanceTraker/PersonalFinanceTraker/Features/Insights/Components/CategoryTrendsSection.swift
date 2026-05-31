import SwiftUI

struct CategoryTrendsSection: View {
    let trends: [CategoryTrend]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InsightsSectionHeader(title: "Category Trends", subtitle: "vs last month")
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
