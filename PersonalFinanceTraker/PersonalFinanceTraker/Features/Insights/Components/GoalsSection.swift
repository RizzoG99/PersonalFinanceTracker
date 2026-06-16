import SwiftUI

struct GoalsSection: View {
    let goals: [GoalModel]
    @Binding var showingAddGoal: Bool
    let transferTotal: (GoalModel) -> Decimal
    let onSelectGoal: (GoalModel) -> Void
    let onDeleteGoal: (GoalModel) -> Void

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
                GlassCard {
                    VStack(spacing: 8) {
                        Image(systemName: "flag.fill")
                            .font(.title2)
                            .foregroundStyle(.accentIndigo.opacity(0.6))
                        Text("Set your first goal")
                            .font(.subheadline.bold())
                            .foregroundStyle(.textMid)
                        Text("Trip fund, emergency buffer, dream purchase — make it visual.")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
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
