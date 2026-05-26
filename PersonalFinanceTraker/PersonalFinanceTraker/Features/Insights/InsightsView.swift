//
//  InsightsView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: InsightsViewModel
    @Binding var showingAddItemView: Bool

    init(context: ModelContext, showingAddItemView: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: InsightsViewModel(repo: TransactionRepository(context: context)))
        _showingAddItemView = showingAddItemView
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    kpiCardsSection
                    barChartSection
                    trendChartSection
                    topCategoriesSection
                    Spacer(minLength: 80)
                }
                .padding(16)
            }
            .appBackground()
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
            .appToolbar(showingAddItemView: $showingAddItemView)
        }
        .onAppear { viewModel.load() }
    }

    // MARK: - Sections

    private var kpiCardsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(
                    icon: "arrow.down",
                    label: "Avg Income",
                    value: formatEUR(viewModel.averageIncome),
                    color: .positive
                )
                StatCard(
                    icon: "arrow.up",
                    label: "Avg Expenses",
                    value: formatEUR(viewModel.averageExpenses),
                    color: .negative
                )
            }
            StatCard(
                icon: "chart.line.uptrend.xyaxis",
                label: "Avg Savings / mo",
                value: formatEUR(viewModel.averageSavings),
                color: .accentIndigo
            )
        }
    }

    private var barChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Income vs Expenses")
                .font(.headline)
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, 4)

            GlassCard {
                if viewModel.chartData.isEmpty {
                    Text("No data")
                        .foregroundStyle(.textDim)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                } else {
                    Chart {
                        ForEach(viewModel.chartData, id: \.period) { dp in
                            BarMark(
                                x: .value("Period", dp.period),
                                y: .value("Income", Double(truncating: dp.income as NSDecimalNumber))
                            )
                            .foregroundStyle(Color.positive.opacity(0.85))
                            .position(by: .value("Type", "Income"))

                            BarMark(
                                x: .value("Period", dp.period),
                                y: .value("Expenses", Double(truncating: dp.expenses as NSDecimalNumber))
                            )
                            .foregroundStyle(Color.negative.opacity(0.85))
                            .position(by: .value("Type", "Expenses"))
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(.textDim)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(.textDim)
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        }
                    }
                    .frame(height: 240)
                }
            }
        }
    }

    private var trendChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending Trend (6 Months)")
                .font(.headline)
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, 4)

            GlassCard {
                if viewModel.trendData.isEmpty {
                    Text("No data")
                        .foregroundStyle(.textDim)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                } else {
                    Chart {
                        ForEach(Array(viewModel.trendData.enumerated()), id: \.offset) { index, value in
                            LineMark(
                                x: .value("Month", index),
                                y: .value("Amount", value)
                            )
                            .foregroundStyle(.negative)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Month", index),
                                y: .value("Amount", value)
                            )
                            .foregroundStyle(.negative)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(.textDim)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(.textDim)
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        }
                    }
                    .frame(height: 200)
                }
            }
        }
    }

    private var topCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Spending Categories")
                .font(.headline)
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(viewModel.topCategories) { cat in
                    InsightsTopCategoryRow(category: cat)
                }
            }
        }
    }
}


#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    return InsightsView(context: container.mainContext, showingAddItemView: .constant(false))
        .environmentObject(ProfileViewModel())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
