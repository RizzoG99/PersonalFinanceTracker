//
//  DashboardView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: DashboardViewModel
    @EnvironmentObject private var transactionListViewModel: TransactionListViewModel

    init(context: ModelContext) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(repo: TransactionRepository(context: context)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    balanceCard
                    if !viewModel.recentTransactions.isEmpty {
                        recentTransactionsSection
                    }
                    savingsGoalCard
                    Spacer(minLength: 80)
                }
                .padding(16)
            }
            .appBackground()
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear { viewModel.load() }
    }

    private var balanceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Total Balance")
                    .font(.subheadline)
                    .foregroundColor(.textMid)

                Text(formatEUR(viewModel.totalBalance))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.textPrimary)

                Divider().opacity(0.15)

                HStack(spacing: 12) {
                    StatCard(icon: "arrow.down",
                             label: "Income",
                             value: "+\(formatEUR(viewModel.monthlyIncome))",
                             color: .positive)

                    StatCard(icon: "arrow.up",
                             label: "Expenses",
                             value: "-\(formatEUR(viewModel.monthlyExpenses))",
                             color: .negative)
                }
            }
        }
    }

    private var savingsGoalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Savings Goal")
                        .font(.subheadline)
                        .foregroundColor(.textMid)
                    Spacer()
                    Text("\(Int(viewModel.savingsGoalProgress * 100))%")
                        .font(.headline)
                        .foregroundColor(.accentIndigo)
                }

                ProgressView(value: min(viewModel.savingsGoalProgress, 1.0))
                    .tint(.accentIndigo)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current")
                            .font(.caption)
                            .foregroundColor(.textDim)
                        Text(formatEUR(viewModel.currentSavings))
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Goal")
                            .font(.caption)
                            .foregroundColor(.textDim)
                        Text(formatEUR(viewModel.savingsGoal))
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                    }
                }
            }
        }
    }

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Transactions")
                .font(.headline)
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 4)
            
            GlassCard {
                VStack(spacing: 8) {
                    ForEach(viewModel.recentTransactions) { tx in
                        Button {
                            transactionListViewModel.transactionToEdit = tx
                        } label: {
                            TransactionItemView(item: tx)
                        }
                        .buttonStyle(.plain)
                        if tx.id != viewModel.recentTransactions.last?.id {
                            Divider()
                                .padding(.horizontal, -16)
                        }
                    }
                }
            }
        }
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
    let vm = TransactionListViewModel(repo: TransactionRepository(context: container.mainContext))
    return DashboardView(context: container.mainContext)
        .environmentObject(vm)
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
