//
//  CategoryTrendRow.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CategoryTrendRow: View {
    let trend: CategoryTrend

    private var trendColor: Color {
        switch trend.direction {
        case .up:   return .negative
        case .down: return .positive
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
                    Text(trend.category.category)
                        .font(.body)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                    Text(String(format: "%.1f%% of total", trend.category.percentage))
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(formatEUR(trend.category.amount))
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                    trendBadge
                }
            }
        }
    }

    private var categoryIcon: some View {
        let info = CategoryInfo.info(for: trend.category.category)
        return ZStack {
            Circle()
                .fill(info.color.opacity(0.18))
                .frame(width: 42, height: 42)
            Image(systemName: info.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(info.color)
        }
    }

    private var trendBadge: some View {
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
    }
}
