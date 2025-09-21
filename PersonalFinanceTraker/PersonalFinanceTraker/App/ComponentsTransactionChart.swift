//
//  TransactionChart.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI
import Charts

/// A reusable chart component for displaying financial transaction data
///
/// This component creates a bar chart showing income and expenses over time periods.
/// Income is displayed as green bars above the baseline, expenses as red bars below.
///
/// ## Usage
/// ```swift
/// let chartData = [
///     ChartDataPoint(period: "Mon", income: 1000, expenses: 500),
///     ChartDataPoint(period: "Tue", income: 800, expenses: 600)
/// ]
/// 
/// TransactionChart(
///     data: chartData,
///     currencyCode: "EUR"
/// )
/// ```
///
/// ## Features
/// - Color-coded bars (green for income, red for expenses)
/// - Formatted currency axis labels
/// - Custom legend
/// - Responsive design
/// - Support for different currencies
public struct TransactionChart: View {
    /// Array of chart data points to display
    public let data: [ChartDataPoint]
    
    /// Currency code for formatting axis labels
    public let currencyCode: String
    
    /// Height of the chart
    public let chartHeight: CGFloat
    
    /// Creates a new transaction chart
    /// - Parameters:
    ///   - data: Array of chart data points
    ///   - currencyCode: Currency code for formatting (defaults to "EUR")
    ///   - chartHeight: Height of the chart (defaults to 200)
    public init(data: [ChartDataPoint], currencyCode: String = "EUR", chartHeight: CGFloat = 200) {
        self.data = data
        self.currencyCode = currencyCode
        self.chartHeight = chartHeight
    }
    
    public var body: some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { index, dataPoint in
                // Income bars (above baseline)
                BarMark(
                    x: .value("Period", dataPoint.period),
                    y: .value("Income", Double(truncating: dataPoint.income as NSDecimalNumber)),
                    width: .ratio(0.7)
                )
                .foregroundStyle(.green)
                .opacity(0.8)
                
                // Expense bars (below baseline, using negative values)
                BarMark(
                    x: .value("Period", dataPoint.period),
                    y: .value("Expenses", -Double(truncating: dataPoint.expenses as NSDecimalNumber)),
                    width: .ratio(0.7)
                )
                .foregroundStyle(.red)
                .opacity(0.8)
            }
        }
        .frame(height: chartHeight)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(Decimal(doubleValue), format: .currency(code: currencyCode).precision(.fractionLength(0)))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartLegend(position: .bottom) {
            HStack {
                LegendItem(color: .green, label: "Income")
                LegendItem(color: .red, label: "Expenses")
            }
        }
    }
}

/// A small legend item for the chart
private struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview("Sample Chart Data") {
    let sampleData = [
        ChartDataPoint(period: "Mon", income: 1000, expenses: 500),
        ChartDataPoint(period: "Tue", income: 800, expenses: 600),
        ChartDataPoint(period: "Wed", income: 1200, expenses: 400),
        ChartDataPoint(period: "Thu", income: 900, expenses: 700),
        ChartDataPoint(period: "Fri", income: 1100, expenses: 800),
        ChartDataPoint(period: "Sat", income: 600, expenses: 300),
        ChartDataPoint(period: "Sun", income: 400, expenses: 200)
    ]
    
    return TransactionChart(data: sampleData, currencyCode: "EUR")
        .padding()
}

#Preview("Empty Chart") {
    TransactionChart(data: [], currencyCode: "USD")
        .padding()
}