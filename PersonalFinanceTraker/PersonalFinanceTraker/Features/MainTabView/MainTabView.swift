//
//  MainTabView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: TabItem = .home
    @State private var showingAddItemView: Bool = false
    @State private var viewModel: TransactionListViewModel
    @State private var dashboardViewModel: DashboardViewModel
    @State private var profileViewModel = ProfileViewModel()
    @State private var appSettings = AppSettings()

    init(context: ModelContext) {
        _viewModel = State(wrappedValue: TransactionListViewModel(repo: TransactionRepository(context: context)))
        _dashboardViewModel = State(wrappedValue: DashboardViewModel(repo: TransactionRepository(context: context)))
    }

    enum TabItem: Hashable {
        case home, activity, insights, credit, search
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: selectedTab == .home ? "house.fill" : "house", value: .home) {
                    DashboardView(showingAddItemView: $showingAddItemView)
                        .payCycleAware { dashboardViewModel.load() }
                }
                Tab("Activity", systemImage: selectedTab == .activity ? "list.bullet.rectangle.fill" : "list.bullet.rectangle", value: .activity, role: .search) {
                    ActivityView(context: modelContext, showingAddItemView: $showingAddItemView)
                        .payCycleAware { viewModel.load() }
                }
                Tab("Compass", systemImage: selectedTab == .insights ? "safari.fill" : "safari", value: .insights) {
                    CompassView(context: modelContext, showingAddItemView: $showingAddItemView)
                }
// Tab("Credit", systemImage: selectedTab == .credit ? "creditcard.fill" : "creditcard", value: .credit) {
//     CreditView(context: modelContext, showingAddItemView: $showingAddItemView)
// }
            }
            .environment(\.symbolVariants, .none)
            .tint(Color.accentIndigo)
            .tabBarMinimizeBehavior(.onScrollDown)
            .environment(viewModel)
            .environment(dashboardViewModel)
            .environment(profileViewModel)
            .environment(appSettings)
            .sheet(isPresented: $showingAddItemView, onDismiss: { dashboardViewModel.load() }) {
                NavigationStack {
                    EditAddTransactionView()
                        .environment(viewModel)
                        .environment(dashboardViewModel)
                }
                .presentationDetents([.large])
                .presentationBackground { AppBackground() }
            }
            .sheet(item: $viewModel.transactionToEdit, onDismiss: { dashboardViewModel.load() }) { item in
                NavigationStack {
                    EditAddTransactionView(item)
                        .environment(viewModel)
                        .environment(dashboardViewModel)
                }
                .presentationDetents([.large])
                .presentationBackground { AppBackground() }
            }
        }
        .appBackground()
        .preferredColorScheme(.dark)
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self, CreditCardModel.self, GoalModel.self])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    do {
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        SampleData.populateModelContext(container.mainContext)
        return MainTabView(context: container.mainContext)
            .modelContainer(container)
    } catch {
        return Text("Failed to create preview container: \(error.localizedDescription)")
    }
}
