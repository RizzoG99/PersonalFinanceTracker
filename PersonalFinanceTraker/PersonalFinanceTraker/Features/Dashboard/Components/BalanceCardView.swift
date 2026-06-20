//
//  BalanceCardView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct BalanceCardView: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
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
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    let repo = TransactionRepository(context: container.mainContext)
    let dashVM = DashboardViewModel(repo: repo)
    return BalanceCardView()
        .environment(dashVM)
        .modelContainer(container)
}
