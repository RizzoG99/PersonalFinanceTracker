import SwiftUI

struct HealthScoreSection: View {
    let healthScore: HealthScore?
    let snapshots: [HealthScoreSnapshot]
    @Binding var ignoreSubscriptions: Bool

    @State private var showingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InsightsSectionHeader(title: "Health Score", subtitle: "How your finances are doing")
            if let score = healthScore {
                HealthScoreCard(healthScore: score, snapshots: snapshots) {
                    showingDetail = true
                }
            }
        }
        .sheet(isPresented: $showingDetail) {
            if let score = healthScore {
                HealthScoreDetailView(
                    healthScore: score,
                    snapshots: snapshots,
                    ignoreSubscriptions: $ignoreSubscriptions
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .onChange(of: ignoreSubscriptions) {
                    showingDetail = false
                }
            }
        }
    }
}
