//
//  CategoryBreakdownView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI
import SwiftData
import Charts

/// A dedicated view for displaying category-based financial breakdowns
///
/// This view shows pie charts breaking down expenses or income by categories,
/// with time period filtering and detailed statistics.
///
/// ## Features
/// - Interactive pie chart showing category breakdowns
/// - Switch between expenses and income views
/// - Time period filtering (week, month, year)
/// - Detailed category list with amounts and percentages
/// - Empty state handling
struct CategoryBreakdownView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionModel.timestamp, order: .reverse) private var items: [TransactionModel]
    
    @State private var selectedTimePeriod: TimePeriod = .month
    @State private var selectedPieChartType: PieChartDataType = .expenses
    
    // Services
    private let pieChartDataService = PieChartDataService()
    
    private var pieChartData: [PieChartDataPoint] {
        pieChartDataService.generatePieChartData(
            from: items,
            for: selectedPieChartType,
            timePeriod: selectedTimePeriod
        )
    }
    
    private var summaryStats: (totalAmount: Decimal, categoryCount: Int) {
        pieChartDataService.getSummaryStats(
            from: items,
            for: selectedPieChartType,
            timePeriod: selectedTimePeriod
        )
    }
    
    var body: some View {
        NavigationView {
            List {
                // Controls Section
                Section {
                    VStack(spacing: 16) {
                        TimePeriodPicker(selection: $selectedTimePeriod)
                        PieChartTypePicker(selection: $selectedPieChartType)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Filters")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                // Pie Chart Section
                Section {
                    VStack(spacing: 16) {
                        CategoryPieChart(
                            data: pieChartData,
                            dataType: selectedPieChartType,
                            currencyCode: "EUR",
                            chartSize: 250
                        )
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("\(selectedPieChartType.description) Breakdown")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                // Summary Stats Section
                if summaryStats.categoryCount > 0 {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            SummaryStatRow(
                                label: "Total \(selectedPieChartType.description):",
                                value: summaryStats.totalAmount,
                                currencyCode: "EUR"
                            )
                            
                            SummaryStatRow(
                                label: "Categories:",
                                value: "\(summaryStats.categoryCount)",
                                isNumber: true
                            )
                            
                            SummaryStatRow(
                                label: "Time Period:",
                                value: selectedTimePeriod.description,
                                isText: true
                            )
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Summary")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
                
                // Detailed Category List
                if !pieChartData.isEmpty {
                    Section {
                        ForEach(pieChartData) { dataPoint in
                            CategoryDetailRow(
                                dataPoint: dataPoint,
                                currencyCode: "EUR"
                            )
                        }
                    } header: {
                        Text("Category Details")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Category Breakdown")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

/// A row showing summary statistics
private struct SummaryStatRow: View {
    let label: String
    let value: Any
    let currencyCode: String?
    let isNumber: Bool
    let isText: Bool
    
    init(label: String, value: Decimal, currencyCode: String) {
        self.label = label
        self.value = value
        self.currencyCode = currencyCode
        self.isNumber = false
        self.isText = false
    }
    
    init(label: String, value: String, isNumber: Bool = false, isText: Bool = false) {
        self.label = label
        self.value = value
        self.currencyCode = nil
        self.isNumber = isNumber
        self.isText = isText
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Group {
                if let currencyCode = currencyCode, let decimalValue = value as? Decimal {
                    Text(decimalValue, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } else if let stringValue = value as? String {
                    Text(stringValue)
                        .font(.subheadline)
                        .fontWeight(isNumber ? .semibold : .medium)
                }
            }
            .foregroundColor(.secondary)
        }
    }
}

/// A detailed row for each category in the breakdown
private struct CategoryDetailRow: View {
    let dataPoint: PieChartDataPoint
    let currencyCode: String
    
    var body: some View {
        HStack {
            // Color indicator
            Circle()
                .fill(dataPoint.color)
                .frame(width: 16, height: 16)
            
            // Category name
            Text(dataPoint.category)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            // Amount and percentage
            VStack(alignment: .trailing, spacing: 2) {
                Text(dataPoint.amount, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(dataPoint.formattedPercentage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    let container = try! ModelContainer(for: TransactionModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    
    // Add sample data
    SampleData.populateModelContext(container.mainContext)
    
    return CategoryBreakdownView()
        .modelContainer(container)
}
