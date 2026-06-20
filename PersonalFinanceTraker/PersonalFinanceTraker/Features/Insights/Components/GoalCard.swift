//
//  GoalCard.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct GoalCard: View {
    let goal: GoalModel
    let currentAmount: Decimal
    let onTap: () -> Void

    private var progress: Double {
        guard goal.targetAmount > 0 else { return 0 }
        return min(1.0, Double(truncating: (currentAmount / goal.targetAmount) as NSDecimalNumber))
    }

    private var goalColor: Color { Color(goal.colorToken) }

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
                        Text(daysLeft.map { "\(max(0, $0))d left" } ?? " ")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                    }

                    Text(goal.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)

                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(goalColor)
                                    .frame(width: max(8, geo.size.width * CGFloat(progress)))
                                    .animation(.easeOut(duration: 0.6), value: progress)
                            }
                    }
                    .frame(height: 6)

                    HStack(spacing: 4) {
                        Text(formatEURCompact(currentAmount))
                            .font(.caption.bold())
                            .foregroundStyle(goalColor)
                        Text("/")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text(formatEURCompact(goal.targetAmount))
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Spacer()
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.caption.bold())
                            .foregroundStyle(.textMid)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .aspectRatio(4/3, contentMode: .fill)
        .clipped()
        .contentShape(Rectangle())
    }
}
