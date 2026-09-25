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
                            // Unlike Activity, this list does not collapse a trip into a
                            // single row, so without the badge a trip expense shows up
                            // here with nothing saying it belongs to one.
                            TransactionItemView(
                                item: tx,
                                showsTravelBadge: true,
                                travel: transactionListViewModel.travel(for: tx)
                            )
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
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    let repo = TransactionActor.make(container)
    let dashVM = DashboardViewModel(repo: repo)
    let txVM = TransactionListViewModel(repo: repo)
    return RecentTransactionsSectionView()
        .environment(dashVM)
        .environment(txVM)
        .modelContainer(container)
}
