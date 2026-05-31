import SwiftUI

struct HabitsSection: View {
    let observations: [HabitObservation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InsightsSectionHeader(title: "Patterns", subtitle: "Recurring spending habits")
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
