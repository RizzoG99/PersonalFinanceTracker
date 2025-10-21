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
    @StateObject private var viewModel: CategoryBreakdownViewModel
    
    init(context: ModelContext) {
        _viewModel = StateObject(wrappedValue: CategoryBreakdownViewModel(repo: TransactionRepository(context: context)))
    }
    
    var body: some View {
        NavigationView {
            List {
                // Controls Section
                Section {
                    VStack(spacing: 16) {
                        TimePeriodPicker(selection: $viewModel.selectedTimePeriod)
                        PieChartTypePicker(selection: $viewModel.selectedPieChartType)
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
                            data: viewModel.pieChartData,
                            dataType: viewModel.selectedPieChartType,
                            currencyCode: "EUR",
                            chartSize: 250
                        )
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("\(viewModel.selectedPieChartType.description) Breakdown")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                // Summary Stats Section
                if viewModel.summaryStats.categoryCount > 0 {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            SummaryStatRow(
                                label: "Total \(viewModel.selectedPieChartType.description):",
                                value: viewModel.summaryStats.totalAmount,
                                currencyCode: "EUR"
                            )
                            
                            SummaryStatRow(
                                label: "Categories:",
                                value: "\(viewModel.summaryStats.categoryCount)",
                                isNumber: true
                            )
                            
                            SummaryStatRow(
                                label: "Time Period:",
                                value: viewModel.selectedTimePeriod.description,
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
                if !viewModel.pieChartData.isEmpty {
                    Section {
                        ForEach(viewModel.pieChartData) { dataPoint in
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
        .onAppear {
            viewModel.load()
        }
    }
}
