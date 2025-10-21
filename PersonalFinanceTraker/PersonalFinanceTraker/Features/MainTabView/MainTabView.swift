//
//  MainTabView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI
import SwiftData

/// Main tab view container for the Personal Finance Tracker app
///
/// This view provides the main navigation structure with two main tabs:
/// 1. Transactions - View and manage financial transactions
/// 2. Category Breakdown - Visual breakdown of expenses/income by categories
/// 
/// Features a native iOS-style add button in the navigation toolbar.
///
/// ## Features
/// - Two-tab navigation with custom icons
/// - Native iOS toolbar add button (similar to Apple Music)
/// - Clean, consistent design with iOS design language
/// - Proper state management for sheets and modals
struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: TabItem = .transactions
    @State var showingAddItemView: Bool = false
    @State private var searchText: String = ""
    @StateObject private var viewModel: TransactionListViewModel
    
    init(context: ModelContext) {
        _viewModel = StateObject(wrappedValue: TransactionListViewModel(repo: TransactionRepository(context: context)))
    }
    
    /// Available tabs in the app
    enum TabItem: String, CaseIterable {
        case transactions = "Transactions"
        case categoryBreakdown = "Categories"
        case plusButton = "Add Transaction"
        case search = "Search"
        
        /// System image for each tab
        var systemImage: String {
            switch self {
            case .transactions: return "list.bullet"
            case .categoryBreakdown: return "chart.pie.fill"
            case .plusButton: return "plus"
            case .search: return "magnifyingglass"
            }
        }
        
        /// Display label for each tab
        var label: String {
            return self.rawValue
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Transactions Tab
            Tab(TabItem.transactions.label, systemImage: TabItem.transactions.systemImage, value: TabItem.transactions) {
                TransactionListMVVM(showingAddItemView: $showingAddItemView)
            }
            
            // Category Breakdown Tab
            Tab(TabItem.categoryBreakdown.label, systemImage: TabItem.categoryBreakdown.systemImage, value: TabItem.categoryBreakdown) {
                CategoryBreakdownView(context: modelContext)
            }
            
            Tab(TabItem.search.label,
                systemImage: TabItem.search.systemImage,
                value: TabItem.search, role: .search) {
                NavigationStack {
                    
                }
            }
        }
        .environmentObject(viewModel)
        .onChange(of: selectedTab) { oldValue, newValue in
//            if newValue == .plusButton {
//                showingAddItemView = true
//                // Reset to previous tab after showing sheet
//                selectedTab = oldValue
//            }
        }
        .sheet(isPresented: $showingAddItemView) {
            NavigationStack {
                EditAddTransactionView()
                    .environmentObject(viewModel)
                    .padding(.top, 32)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $viewModel.transactionToEdit) { item in
            NavigationStack {
                EditAddTransactionView(item)
                    .environmentObject(viewModel)
                    .padding(.top, 32)
            }
            .presentationDetents([.medium])
        }
        .searchable(text: $searchText)
        .accentColor(.blue)
    }
}

#Preview {
    let container = try! ModelContainer(for: TransactionModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    
    // Add sample data
    SampleData.populateModelContext(container.mainContext)
    
    return MainTabView(context: container.mainContext)
        .modelContainer(container)
}
