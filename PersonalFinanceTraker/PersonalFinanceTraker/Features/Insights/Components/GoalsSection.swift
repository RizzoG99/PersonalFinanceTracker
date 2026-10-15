import SwiftUI

struct GoalsSection: View {
    let goals: [GoalSnapshot]
    @Binding var showingAddGoal: Bool
    let transferTotal: (GoalSnapshot) -> Decimal
    let projection: (GoalSnapshot) -> GoalProjection
    let onSelectGoal: (GoalSnapshot) -> Void
    let onDeleteGoal: (GoalSnapshot) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var singleColumn: Bool { dynamicTypeSize >= .xxLarge }
    @State private var width: CGFloat = 0

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
                // ponytail: Grid, not LazyVGrid, so cards in a row take the tallest one's height
                // (a wrapped projection line made neighbours uneven). Not lazy: goals are a handful.
                let columns = columnCount
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    ForEach(Array(stride(from: 0, to: goals.count, by: columns)), id: \.self) { start in
                        GridRow {
                            ForEach(goals[start..<min(start + columns, goals.count)]) { goal in
                                card(goal)
                            }
                        }
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// One column from xxLarge text up (a half-width card truncates "1.800 € / 3.000 €");
    /// otherwise as many ~240pt cards as fit, never fewer than 2 — 3 on a wide iPad.
    private var columnCount: Int {
        if singleColumn { return 1 }
        return max(2, Int((width + 12) / (240 + 12)))
    }

    private func card(_ goal: GoalSnapshot) -> some View {
        GoalCard(goal: goal, currentAmount: transferTotal(goal), projection: projection(goal)) {
            onSelectGoal(goal)
        }
        // Cards fill their column: height follows content now, so a wide iPad column no longer
        // makes them tall, and a width cap only left a gap between the columns.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            Button(role: .destructive) {
                onDeleteGoal(goal)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
