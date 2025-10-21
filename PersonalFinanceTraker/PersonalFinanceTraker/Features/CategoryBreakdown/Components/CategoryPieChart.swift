//
//  CategoryPieChart.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI
import Charts

/// A reusable pie chart component for displaying category-based financial data
///
/// This component creates a pie chart showing the breakdown of expenses or income by categories.
/// Each category is represented by a colored segment with corresponding percentage.
///
/// ## Usage
/// ```swift
/// let pieData = [
///     PieChartDataPoint(category: "Food", amount: 500, color: .blue, percentage: 35.7),
///     PieChartDataPoint(category: "Transport", amount: 300, color: .green, percentage: 21.4)
/// ]
/// 
/// CategoryPieChart(
///     data: pieData,
///     dataType: .expenses,
///     currencyCode: "EUR"
/// )
/// ```
///
/// ## Features
/// - Interactive pie chart with colored segments
/// - Category legend with amounts and percentages
/// - Support for both expenses and income
/// - Responsive design
/// - Empty state handling
public struct CategoryPieChart: View {
    /// Array of pie chart data points to display
    public let data: [PieChartDataPoint]
    
    /// Type of data being displayed (expenses or income)
    public let dataType: PieChartDataType
    
    /// Currency code for formatting amounts
    public let currencyCode: String
    
    /// Size of the pie chart
    public let chartSize: CGFloat
    
    /// Creates a new category pie chart
    /// - Parameters:
    ///   - data: Array of pie chart data points
    ///   - dataType: Whether showing expenses or income
    ///   - currencyCode: Currency code for formatting (defaults to "EUR")
    ///   - chartSize: Size of the pie chart (defaults to 200)
    public init(
        data: [PieChartDataPoint],
        dataType: PieChartDataType,
        currencyCode: String = "EUR",
        chartSize: CGFloat = 200
    ) {
        self.data = data
        self.dataType = dataType
        self.currencyCode = currencyCode
        self.chartSize = chartSize
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            if data.isEmpty {
                EmptyPieChartView(dataType: dataType)
            } else {
                // Pie Chart
                Chart(data, id: \.id) { dataPoint in
                    SectorMark(
                        angle: .value("Amount", Double(truncating: dataPoint.amount as NSDecimalNumber)),
                        innerRadius: .ratio(0.4),
                        angularInset: 2
                    )
                    .foregroundStyle(dataPoint.color)
                    .opacity(0.8)
                }
                .frame(height: chartSize)
                .chartLegend(.hidden)
                
                // Category Legend
                CategoryLegendView(data: data, currencyCode: currencyCode)
            }
        }
    }
}

/// Legend view showing categories with colors, amounts, and percentages
private struct CategoryLegendView: View {
    let data: [PieChartDataPoint]
    let currencyCode: String
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 8) {
            ForEach(data) { dataPoint in
                CategoryLegendItem(
                    dataPoint: dataPoint,
                    currencyCode: currencyCode
                )
            }
        }
    }
}

/// Individual legend item for a category
private struct CategoryLegendItem: View {
    let dataPoint: PieChartDataPoint
    let currencyCode: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Color indicator
            Circle()
                .fill(dataPoint.color)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                // Category name
                Text(dataPoint.category)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                // Amount and percentage
                HStack {
                    Text(dataPoint.amount, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("(\(dataPoint.formattedPercentage))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray6))
        )
    }
}

/// Empty state view when no data is available
private struct EmptyPieChartView: View {
    let dataType: PieChartDataType
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No \(dataType.description)")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("No \(dataType.description.lowercased()) data available for the selected time period.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(height: 200)
    }
}

#Preview("Sample Expenses Pie Chart") {
    let sampleData = [
        PieChartDataPoint(category: "Food & Dining", amount: 800, color: .blue, percentage: 40.0),
        PieChartDataPoint(category: "Transportation", amount: 400, color: .green, percentage: 20.0),
        PieChartDataPoint(category: "Shopping", amount: 300, color: .orange, percentage: 15.0),
        PieChartDataPoint(category: "Entertainment", amount: 250, color: .red, percentage: 12.5),
        PieChartDataPoint(category: "Utilities", amount: 200, color: .purple, percentage: 10.0),
        PieChartDataPoint(category: "Other", amount: 50, color: .pink, percentage: 2.5)
    ]
    
    return CategoryPieChart(
        data: sampleData,
        dataType: .expenses,
        currencyCode: "EUR"
    )
    .padding()
}

#Preview("Empty Pie Chart") {
    CategoryPieChart(
        data: [],
        dataType: .income,
        currencyCode: "USD"
    )
    .padding()
}

#Preview("Income Pie Chart") {
    let sampleData = [
        PieChartDataPoint(category: "Salary", amount: 3000, color: .green, percentage: 75.0),
        PieChartDataPoint(category: "Freelancing", amount: 800, color: .blue, percentage: 20.0),
        PieChartDataPoint(category: "Investments", amount: 200, color: .orange, percentage: 5.0)
    ]
    
    return CategoryPieChart(
        data: sampleData,
        dataType: .income,
        currencyCode: "EUR"
    )
    .padding()
}