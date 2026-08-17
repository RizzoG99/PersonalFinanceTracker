//
//  GoalCard.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct GoalCard: View {
    let goal: GoalSnapshot
    let currentAmount: Decimal
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
                            .fill(Color.hairline)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(goalColor)
                                    .frame(width: max(8, geo.size.width * CGFloat(progress)))
                                    .animation(.easeOut(duration: 0.6), value: progress)
                            }
                    }
                    .frame(height: 6)

                    HStack(spacing: 4) {
                        Text(currentAmount.formattedEUR())
                            .font(.caption.bold())
                            .foregroundStyle(goalColor)
                            .privacyBlur()
                        Text("/")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text(goal.targetAmount.formattedEUR())
                            .font(.caption)
                            .foregroundStyle(.textDim)
                            .privacyBlur()
                        Spacer()
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.caption.bold())
                            .foregroundStyle(.textMid)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        // ponytail: the 4:3 ratio is what made these cards ~500pt tall on iPad — at a 640pt-wide
        // grid column the ratio, not the content, decides the height, and the content (~150pt)
        // leaves the rest empty. Capping the width first keeps the ratio producing a phone-sized
        // card on any screen. Cap it at the width iPhone already gives them, so iPhone is
        // unchanged and iPad simply stops stretching.
        .frame(maxWidth: 340)
        .aspectRatio(4/3, contentMode: .fill)
        .clipped()
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
