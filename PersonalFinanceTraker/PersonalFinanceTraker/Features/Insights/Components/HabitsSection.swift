import SwiftUI

struct HabitsSection: View {
    let observations: [HabitObservation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Patterns")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Text("Recurring spending habits")
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
            if observations.isEmpty {
                InsightsEmptyCard(
                    message: "No recurring patterns detected yet",
                    subtitle: "Patterns appear after consistent weekly spending in a category"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(observations) { obs in
                        HabitInsightRow(observation: obs)
                    }
                }
            }
        }
    }
}
