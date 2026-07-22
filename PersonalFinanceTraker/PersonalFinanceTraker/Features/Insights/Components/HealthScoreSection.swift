import SwiftUI

struct HealthScoreSection: View {
    let healthScore: HealthScore?
    let snapshots: [HealthScoreSnapshotData]
    let payCycleStartDay: Int
    @Binding var ignoreSubscriptions: Bool

    @State private var showingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Health Score")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Text("How your finances are doing")
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
            if let score = healthScore {
                HealthScoreCard(healthScore: score, snapshots: snapshots) {
                    showingDetail = true
                }
            } else {
                EmptyStateView(
                    icon: "gauge.medium",
                    message: "Add transactions to unlock your Health Score",
                    subtitle: "Your score builds from at least a few weeks of activity."
                )
            }
        }
        .sheet(isPresented: $showingDetail) {
            if let score = healthScore {
                HealthScoreDetailView(
                    healthScore: score,
                    snapshots: snapshots,
                    payCycleStartDay: payCycleStartDay,
                    ignoreSubscriptions: $ignoreSubscriptions
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}
