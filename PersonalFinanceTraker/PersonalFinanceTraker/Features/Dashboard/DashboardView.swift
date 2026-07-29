//
//  DashboardView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DashboardViewModel.self) private var viewModel
    @Binding var showingAddItemView: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    GreetingHeaderView()
                    BalanceCardView()
                    if let callout = viewModel.anomalyCallout {
                        AnomalyCalloutView(message: callout.message) {
                            viewModel.dismissAnomaly()
                        }
                    }
                    ForEach(viewModel.nearLimitBudgets) { progress in
                        BudgetProgressBarView(progress: progress)
                    }
                    if viewModel.hasNoTransactions {
                        EmptyStateView(
                            icon: "plus.circle",
                            message: "Add your first transaction",
                            subtitle: "Track an expense or income to see your balance grow.",
                            actionTitle: "Add Transaction",
                            action: { showingAddItemView = true }
                        )
                    }
                    if !viewModel.recentTransactions.isEmpty {
                        RecentTransactionsSectionView()
                    }
                    Spacer(minLength: 80)
                }
                .padding(16)
            }
            .appBackground()
            .navigationBarTitleDisplayMode(.inline)
            .appToolbar(showingAddItemView: $showingAddItemView)
        }
        .task { viewModel.load() }
    }
}


#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    let repo = TransactionActor.make(container)
    let dashVM = DashboardViewModel(repo: repo)
    return DashboardView(showingAddItemView: .constant(false))
        .environment(dashVM)
        .environment(ProfileViewModel())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
