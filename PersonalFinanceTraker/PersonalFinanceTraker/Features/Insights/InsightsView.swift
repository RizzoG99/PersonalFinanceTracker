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

    init(context: ModelContext) {
        _viewModel = StateObject(wrappedValue: InsightsViewModel(repo: TransactionRepository(context: context)))
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
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 4)

            GlassCard {
                if viewModel.chartData.isEmpty {
                    Text("No data")
                        .foregroundColor(.textDim)
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
                            AxisValueLabel().foregroundStyle(Color.textDim)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(Color.textDim)
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
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 4)

            GlassCard {
                if viewModel.trendData.isEmpty {
                    Text("No data")
                        .foregroundColor(.textDim)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                } else {
                    Chart {
                        ForEach(Array(viewModel.trendData.enumerated()), id: \.offset) { index, value in
                            LineMark(
                                x: .value("Month", index),
                                y: .value("Amount", value)
                            )
                            .foregroundStyle(Color.negative)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Month", index),
                                y: .value("Amount", value)
                            )
                            .foregroundStyle(Color.negative)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(Color.textDim)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(Color.textDim)
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
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(viewModel.topCategories) { cat in
                    InsightsTopCategoryRow(category: cat)
                }
            }
        }
    }
}

// MARK: - Subcomponents

private struct InsightsKPICard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.textDim)
                Text(value)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 90)
        }
    }
}

private struct InsightsTopCategoryRow: View {
    let category: PieChartDataPoint

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.category)
                        .font(.body)
                        .foregroundColor(.textPrimary)
                    Text(String(format: "%.1f%%", category.percentage))
                        .font(.caption)
                        .foregroundColor(.textDim)
                }
                Spacer()
                Text(formatEUR(category.amount))
                    .font(.headline)
                    .foregroundColor(.negative)
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
        .cornerRadius(12)
    }
}

private func formatEUR(_ value: Decimal) -> String {
    let fmt = NumberFormatter()
    fmt.numberStyle = .currency
    fmt.currencyCode = "EUR"
    return fmt.string(from: value as NSDecimalNumber) ?? "€0.00"
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    return InsightsView(context: container.mainContext)
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
