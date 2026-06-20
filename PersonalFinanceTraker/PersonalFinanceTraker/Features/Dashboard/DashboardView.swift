//
//  DashboardView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(ProfileViewModel.self) private var profileViewModel
    @Environment(TransactionListViewModel.self) private var transactionListViewModel
    @Binding var showingAddItemView: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    greetingHeader
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
            .navigationBarTitleDisplayMode(.inline)
            .appToolbar(showingAddItemView: $showingAddItemView)
        }
        .onAppear { viewModel.load() }
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profileViewModel.greeting)
                .font(.title2)
                .foregroundStyle(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var balanceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Total Balance")
                    .font(.subheadline)
                    .foregroundStyle(.textMid)

                Text(formatEUR(viewModel.totalBalance))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.textPrimary)

                Divider().opacity(0.15)

                Text(viewModel.financialMonthLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                        .foregroundStyle(.textMid)
                    Spacer()
                    Text("\(Int(viewModel.savingsGoalProgress * 100))%")
                        .font(.headline)
                        .foregroundStyle(.accentIndigo)
                }

                ProgressView(value: min(viewModel.savingsGoalProgress, 1.0))
                    .tint(.accentIndigo)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text(formatEUR(viewModel.currentSavings))
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Goal")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text(formatEUR(viewModel.savingsGoal))
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                    }
                }
            }
        }
    }

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Transactions")
                .font(.headline)
                .foregroundStyle(.textPrimary)
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


#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    let repo = TransactionRepository(context: container.mainContext)
    let vm = TransactionListViewModel(repo: repo)
    let dashVM = DashboardViewModel(repo: repo)
    return DashboardView(showingAddItemView: .constant(false))
        .environment(vm)
        .environment(dashVM)
        .environment(ProfileViewModel())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
