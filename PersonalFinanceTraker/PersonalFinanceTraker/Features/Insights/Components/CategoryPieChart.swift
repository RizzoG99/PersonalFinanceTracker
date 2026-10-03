//
//  CategoryPieChart.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI
import Charts

/// Donut of category shares. No legend: in the Insights explorer the category list right below
/// it is the legend (same colours, plus amount, % and Δ). Callers handle the empty state.
struct CategoryPieChart: View {
    let data: [PieChartDataPoint]
    var chartSize: CGFloat = 200

    var body: some View {
        Chart(data) { dataPoint in
            SectorMark(
                angle: .value("Amount", Double(truncating: dataPoint.amount as NSDecimalNumber)),
                innerRadius: .ratio(0.55),
                angularInset: 2
            )
            .foregroundStyle(dataPoint.color)
            .cornerRadius(3)
            .accessibilityLabel(dataPoint.category.removingLeadingEmoji.localizedCategoryDisplay)
            .accessibilityValue(dataPoint.formattedPercentage)
        }
        .frame(height: chartSize)
        .chartLegend(.hidden)
    }
}

#Preview {
    CategoryPieChart(data: [
        PieChartDataPoint(category: "Food & Dining", amount: 800, color: .blue, percentage: 40.0),
        PieChartDataPoint(category: "Transportation", amount: 400, color: .green, percentage: 20.0),
        PieChartDataPoint(category: "Shopping", amount: 300, color: .orange, percentage: 15.0)
    ])
    .padding()
}
