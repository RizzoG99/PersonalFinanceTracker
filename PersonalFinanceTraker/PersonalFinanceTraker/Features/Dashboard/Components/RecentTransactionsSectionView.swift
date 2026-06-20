//
//  RecentTransactionsSectionView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct RecentTransactionsSectionView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(TransactionListViewModel.self) private var transactionListViewModel

    var body: some View {
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
    let dashVM = DashboardViewModel(repo: repo)
    let txVM = TransactionListViewModel(repo: repo)
    return RecentTransactionsSectionView()
        .environment(dashVM)
        .environment(txVM)
        .modelContainer(container)
}
