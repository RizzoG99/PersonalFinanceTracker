//
//  CategoryTrendRow.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CategoryTrendRow: View {
    let trend: CategoryTrend
    /// Income rising is good news, spending rising isn't — flips which way reads green.
    var isIncome = false
    @Environment(AppSettings.self) private var appSettings: AppSettings?

    private var trendColor: Color {
        switch trend.direction {
        case .up:   return isIncome ? .positive : .negative
        case .down: return isIncome ? .negative : .positive
        case .flat: return .textDim
        }
    }

    private var trendArrow: String {
        switch trend.direction {
        case .up:   return "arrow.up"
        case .down: return "arrow.down"
        case .flat: return "minus"
        }
    }

    var body: some View {
        GlassCard(borderRadius: 14) {
            HStack(spacing: 12) {
                categoryIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(trend.category.category.removingLeadingEmoji.localizedCategoryDisplay)
                        .font(.body)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                    Text(String(
                        format: String(localized: "%.1f%% of total"),
                        locale: .current,
                        trend.category.percentage
                    ))
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(trend.category.amount.formattedEUR())
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                        .privacyBlur()
                    trendBadge
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trend.category.category.removingLeadingEmoji.localizedCategoryDisplay)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let share = String(format: String(localized: "%.1f%% of total"), locale: .current, trend.category.percentage)
        let change: String = if trend.isNew {
            String(localized: "new")
        } else {
            switch trend.direction {
            case .up: String(localized: "up \(Int(abs(trend.changePercent).rounded()))% from previous period")
            case .down: String(localized: "down \(Int(abs(trend.changePercent).rounded()))% from previous period")
            case .flat: String(localized: "about the same as previous period")
            }
        }
        // The amount is left out while amounts are hidden (shake-to-hide), same as on screen.
        let amount = (appSettings?.hideAmounts ?? false) ? String(localized: "Amount hidden") : trend.category.amount.formattedEUR()
        return [amount, share, change].joined(separator: ", ")
    }

    private var categoryIcon: some View {
        // Prefer the category's own saved icon and colour, like the Activity rows do
        // (TransactionItemView) — `CategoryInfo`'s keyword table only knows the seeded names,
        // so a user-created category used to land on the generic fallback glyph (#153).
        let info = CategoryInfo.info(for: trend.category.category)
        let symbol = trend.category.systemImage ?? info.symbol
        let tint = trend.category.color
        return ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 42, height: 42)
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
        }
    }

    private var trendBadge: some View {
        if trend.isNew {
            return AnyView(
                Text(String(localized: "new"))
                    .font(.caption.bold())
                    .foregroundStyle(.textDim)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.textDim.opacity(0.12))
                    .clipShape(.capsule)
            )
        } else {
            return AnyView(
                HStack(spacing: 3) {
                    Image(systemName: trendArrow)
                        .font(.caption2.bold())
                    Text(String(format: "%.0f%%", abs(trend.changePercent)))
                        .font(.caption.bold())
                }
                .foregroundStyle(trendColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(trendColor.opacity(0.12))
                .clipShape(.capsule)
            )
        }
    }
}
