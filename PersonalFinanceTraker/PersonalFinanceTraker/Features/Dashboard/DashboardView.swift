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
                    if !viewModel.recentTransactions.isEmpty {
                        RecentTransactionsSectionView()
                    }
                    SavingsGoalCardView()
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
}


#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    let repo = TransactionRepository(context: container.mainContext)
    let dashVM = DashboardViewModel(repo: repo)
    return DashboardView(showingAddItemView: .constant(false))
        .environment(dashVM)
        .environment(ProfileViewModel())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
