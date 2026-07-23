import SwiftUI

struct GoalsSection: View {
    let goals: [GoalSnapshot]
    @Binding var showingAddGoal: Bool
    let transferTotal: (GoalSnapshot) -> Decimal
    let onSelectGoal: (GoalSnapshot) -> Void
    let onDeleteGoal: (GoalSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goals")
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                    Text("What you're saving toward")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
                Spacer()
                Button("Add Goal", systemImage: "plus.circle.fill") {
                    showingAddGoal = true
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(.accentIndigo)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }

            if goals.isEmpty {
                EmptyStateView(
                    icon: "flag.fill",
                    message: "Set your first goal",
                    subtitle: "Trip fund, emergency buffer, dream purchase — make it visual."
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(goals) { goal in
                        GoalCard(goal: goal, currentAmount: transferTotal(goal)) {
                            onSelectGoal(goal)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                onDeleteGoal(goal)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}
