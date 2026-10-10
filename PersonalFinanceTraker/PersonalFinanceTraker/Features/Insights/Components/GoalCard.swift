//
//  GoalCard.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct GoalCard: View {
    let goal: GoalSnapshot
    let currentAmount: Decimal
    let projection: GoalProjection
    let onTap: () -> Void

    private var progress: Double {
        guard goal.targetAmount > 0 else { return 0 }
        return min(1.0, Double(truncating: (currentAmount / goal.targetAmount) as NSDecimalNumber))
    }

    private var goalColor: Color { Color(categoryToken: goal.colorToken) }

    private var daysLeft: Int? {
        guard let deadline = goal.deadline else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: deadline).day
    }

    var body: some View {
        Button(action: onTap) {
            GlassCard(borderRadius: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 0) {
                        Image(systemName: goal.iconName)
                            .font(.title3.bold())
                            .foregroundStyle(goalColor)
                        Spacer()
                        // Past the deadline the projection line says "Overdue"; "0d left" would just repeat it.
                        Text(daysLeft.flatMap { $0 >= 0 ? "\($0)d left" : nil } ?? " ")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                    }

                    Text(goal.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)

                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.hairline)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(goalColor)
                                    .frame(width: max(8, geo.size.width * CGFloat(progress)))
                                    .animation(.easeOut(duration: 0.6), value: progress)
                            }
                    }
                    .frame(height: 6)

                    // Whole euros on one line: with cents a half-width column broke "1.800,00 €"
                    // mid-number. The detail sheet keeps the exact amounts.
                    HStack(spacing: 4) {
                        Text("\(Text(currentAmount.wholeEuros).bold().foregroundStyle(goalColor)) / \(goal.targetAmount.wholeEuros)")
                            .foregroundStyle(.textDim)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .privacyBlur()
                        Spacer(minLength: 4)
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.bold())
                            .foregroundStyle(.textMid)
                    }

                    GoalProjectionLine(projection: projection)
                }
                // Fills the grid row's height (content pinned to the top), so neighbours match.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
