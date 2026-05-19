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
    @State var showingAddItemView: Bool = false
    @StateObject private var viewModel: TransactionListViewModel

    init(context: ModelContext) {
        _viewModel = StateObject(wrappedValue: TransactionListViewModel(repo: TransactionRepository(context: context)))
    }

    enum TabItem: Hashable {
        case home, activity, insights, credit
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: selectedTab == .home ? "house.fill" : "house", value: .home) {
                    DashboardView(context: modelContext)
                }
                Tab("Activity", systemImage: selectedTab == .activity ? "list.bullet.rectangle.fill" : "list.bullet.rectangle", value: .activity) {
                    ActivityView(context: modelContext, showingAddItemView: $showingAddItemView)
                }
                Tab("Insights", systemImage: selectedTab == .insights ? "chart.bar.fill" : "chart.bar", value: .insights) {
                    InsightsView(context: modelContext)
                }
                Tab("Credit", systemImage: selectedTab == .credit ? "creditcard.fill" : "creditcard", value: .credit) {
                    CreditView()
                }
            }
            .tabViewBottomAccessory(content: {
                // Floating action button
                Button {
                    showingAddItemView = true
                } label: {
    //                GlassCard(tint: Color.accentIndigo, borderRadius: 24) {
                    HStack {
                        Label("Add Transaction", systemImage: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color.accentIndigo)
                    }
                    .padding(4)
    //                }
    //                .shadow(color: Color.accentIndigo.opacity(0.5), radius: 10, x: 0, y: 4)
                        
                }
            })
            .environment(\.symbolVariants, .none)
            .tint(Color.accentIndigo)
            .tabBarMinimizeBehavior(.onScrollDown)
            .environmentObject(viewModel)
            .sheet(isPresented: $showingAddItemView) {
                NavigationStack {
                    EditAddTransactionView()
                        .environmentObject(viewModel)
                }
                .presentationDetents([.medium, .large])
                .presentationBackground { AppBackground() }
            }
            .sheet(item: $viewModel.transactionToEdit) { item in
                NavigationStack {
                    EditAddTransactionView(item)
                        .environmentObject(viewModel)
                }
                .presentationDetents([.medium, .large])
                .presentationBackground { AppBackground() }
            }
        }
        .appBackground()
        .preferredColorScheme(.dark)
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
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
