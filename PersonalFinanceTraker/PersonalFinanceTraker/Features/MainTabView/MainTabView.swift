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
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: TabItem = .home
    @State private var showingAddItemView: Bool = false
    @State private var viewModel: TransactionListViewModel
    @State private var dashboardViewModel: DashboardViewModel
    @State private var profileViewModel = ProfileViewModel()
    @State private var appSettings = AppSettings()

    init(modelContainer: ModelContainer) {
        let actor = TransactionActor(modelContainer: modelContainer)
        _viewModel = State(wrappedValue: TransactionListViewModel(repo: actor))
        _dashboardViewModel = State(wrappedValue: DashboardViewModel(repo: actor))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: selectedTab == .home ? "house.fill" : "house", value: .home) {
                    DashboardView(showingAddItemView: $showingAddItemView)
                        .payCycleAware { dashboardViewModel.load() }
                }
                Tab("Activity", systemImage: selectedTab == .activity ? "list.bullet.rectangle.fill" : "list.bullet.rectangle", value: .activity) {
                    ActivityView(showingAddItemView: $showingAddItemView)
                        .payCycleAware { viewModel.load() }
                }
                Tab("Insights", systemImage: "chart.line.uptrend.xyaxis", value: .insights) {
                    CompassView(context: modelContext, showingAddItemView: $showingAddItemView)
                }
// Tab("Credit", systemImage: selectedTab == .credit ? "creditcard.fill" : "creditcard", value: .credit) {
//     CreditView(context: modelContext, showingAddItemView: $showingAddItemView)
// }
            }
            .environment(\.symbolVariants, .none)
            .tint(Color.accentIndigo)
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
            .sheet(item: $viewModel.transactionToEdit, onDismiss: {
                // Skip reload if a deletion is pending — dashboard reloads when the snackbar settles
                if !viewModel.showUndoBanner { dashboardViewModel.load() }
            }) { item in
                NavigationStack {
                    EditAddTransactionView(item)
                        .environment(viewModel)
                        .environment(dashboardViewModel)
                }
                .presentationDetents([.large])
                .presentationBackground { AppBackground() }
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.showUndoBanner {
                UndoDeleteBanner(
                    count: viewModel.pendingDeletion.count,
                    progress: viewModel.deleteProgress,
                    onUndo: viewModel.undoDelete
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.showUndoBanner)
        .onChange(of: viewModel.pendingDeletion) { _, pending in
            if !pending.isEmpty { dashboardViewModel.optimisticRemove(ids: pending.map(\.id)) }
        }
        .onChange(of: viewModel.showUndoBanner) { _, isShowing in
            if !isShowing { dashboardViewModel.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await viewModel.commitPendingDeletion() }
            }
        }
        .task { viewModel.load() }  // ponytail: pre-warm Activity while user is on Home; isLoaded guard makes repeat a no-op
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
        return MainTabView(modelContainer: container)
            .modelContainer(container)
    } catch {
        return Text("Failed to create preview container: \(error.localizedDescription)")
    }
}
