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
    @StateObject private var viewModel: TransactionListViewModel
    @StateObject private var profileViewModel = ProfileViewModel()

    init(context: ModelContext) {
        _viewModel = StateObject(wrappedValue: TransactionListViewModel(repo: TransactionRepository(context: context)))
    }

    enum TabItem: Hashable {
        case home, activity, insights, credit, search
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: selectedTab == .home ? "house.fill" : "house", value: .home) {
                    DashboardView(context: modelContext, showingAddItemView: $showingAddItemView)
                }
                Tab("Activity", systemImage: selectedTab == .activity ? "list.bullet.rectangle.fill" : "list.bullet.rectangle", value: .activity, role: .search) {
                    ActivityView(context: modelContext, showingAddItemView: $showingAddItemView)
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
            .environmentObject(viewModel)
            .environmentObject(profileViewModel)
            .sheet(isPresented: $showingAddItemView) {
                NavigationStack {
                    EditAddTransactionView()
                        .environmentObject(viewModel)
                }
                .presentationDetents([.large])
                .presentationBackground { AppBackground() }
            }
            .sheet(item: $viewModel.transactionToEdit) { item in
                NavigationStack {
                    EditAddTransactionView(item)
                        .environmentObject(viewModel)
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
