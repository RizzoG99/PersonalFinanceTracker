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
                InsightsEmptyCard(message: "More data needed to detect patterns")
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
