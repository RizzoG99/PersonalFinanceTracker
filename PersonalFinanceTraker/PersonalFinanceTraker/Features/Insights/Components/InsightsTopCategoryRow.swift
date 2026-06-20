//
//  InsightsTopCategoryRow.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct InsightsTopCategoryRow: View {
    let category: PieChartDataPoint

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.category)
                        .font(.body)
                        .foregroundStyle(.textPrimary)
                    Text(String(format: "%.1f%%", category.percentage))
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
                Spacer()
                Text(category.amount.formattedEUR())
                    .font(.headline)
                    .foregroundStyle(.negative)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.bg2.opacity(0.6))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(category.color)
                        .frame(width: geo.size.width * CGFloat(category.percentage / 100))
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(Color.bg2.opacity(0.3))
        .clipShape(.rect(cornerRadius: 12))
    }
}

