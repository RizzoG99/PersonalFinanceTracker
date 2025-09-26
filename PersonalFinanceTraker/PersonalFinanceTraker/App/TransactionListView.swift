//
//  TransactionListView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI
import SwiftData
import Charts

/// A dedicated view for displaying and managing financial transactions
///
/// This view shows transaction history with charts, grouped by dates,
/// and provides functionality to add, edit, and delete transactions.
///
/// ## Features
/// - Interactive bar chart showing income vs expenses over time
/// - Time period filtering (week, month, year)
/// - Grouped transaction list by date
/// - Add, edit, and delete transactions
/// - Swipe to delete functionality
struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @State var itemToEdit: TransactionModel? = nil
    @Query(sort: \TransactionModel.timestamp, order: .reverse) private var items: [TransactionModel]
    @State private var selectedTimePeriod: TimePeriod = .month
    @Binding private var searchText: String
    
    init(searchText: Binding<String>) {
        self._searchText = searchText
    }
    
    // Services
    private let dateFormatter = DateFormattingService()
    private let chartDataService = ChartDataService()
    
    private var filteredItems: [TransactionModel] {
        if searchText.isEmpty {
            return items
        } else {
            return items.filter { item in
                item.note.localizedCaseInsensitiveContains(searchText) ||
                item.amount.description.localizedCaseInsensitiveContains(searchText) ||
                item.category.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var groupedItems: [(String, [TransactionModel])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredItems) { item in
            calendar.startOfDay(for: item.timestamp)
        }
        
        return grouped.map { (date, items) in
            (dateFormatter.formatTransactionDate(date), items.sorted { $0.timestamp > $1.timestamp })
        }.sorted { first, second in
            // Sort sections by date (newest first)
            let firstDate = calendar.startOfDay(for: first.1.first?.timestamp ?? Date())
            let secondDate = calendar.startOfDay(for: second.1.first?.timestamp ?? Date())
            return firstDate > secondDate
        }
    }
    
    private func totalForDate(items: [TransactionModel]) -> Decimal {
        items.reduce(0) { $0 + $1.amount }
    }
    
    private var totalIncome: Decimal {
        filteredItems.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
    }
    
    private var totalExpenses: Decimal {
        filteredItems.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount }
    }
    
    private var chartData: [ChartDataPoint] {
        chartDataService.generateChartData(from: filteredItems, for: selectedTimePeriod)
    }
    
    var body: some View {
        NavigationView {
            List {
                // Chart Section
                Section {
                    VStack(spacing: 16) {
                        TimePeriodPicker(selection: $selectedTimePeriod)
                        
                        TransactionChart(
                            data: chartData,
                            currencyCode: "EUR"
                        )
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Transaction Summary")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                // Transaction List
                ForEach(groupedItems, id: \.0) { dateString, dayItems in
                    Section {
                        ForEach(dayItems) { item in
                            Button(action: {
                                itemToEdit = item
                            }) {
                                TransactionItemView(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            deleteItemsFromSection(dayItems: dayItems, offsets: offsets)
                        }
                    } header: {
                        TransactionSectionHeader(
                            dateString: dateString,
                            totalAmount: totalForDate(items: dayItems),
                            currencyCode: "EUR"
                        )
                    }
                }
            }
            .navigationTitle("Transactions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {    
                        EditButton()
                    }
                }
                #if DEBUG
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: loadSampleData) {
                        Label("Load Sample Data", systemImage: "arrow.clockwise")
                    }
                }
                #endif
            }
        }
        .sheet(item: $itemToEdit) { item in
            NavigationStack {
                TransactionView(transaction: item)
                    .padding(.top, 32)
            }
            .presentationDetents([.medium])
        }
    }
    
    #if DEBUG
    private func loadSampleData() {
        // Clear existing data
        for item in items {
            modelContext.delete(item)
        }
        
        // Add sample data
        SampleData.populateModelContext(modelContext)
        
        print("Sample data reloaded")
    }
    #endif

    private func deleteItemsFromSection(dayItems: [TransactionModel], offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                if let itemToDelete = items.first(where: { $0.id == dayItems[index].id }) {
                    modelContext.delete(itemToDelete)
                }
            }
            do {
                try modelContext.save()
            } catch {
                // Handle the error appropriately
                print("Failed to save context: \(error)")
            }
        }
    }
}

#Preview {
    @Previewable @State var searchText = ""
    let container = try! ModelContainer(for: TransactionModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    // Add sample data
    SampleData.populateModelContext(container.mainContext)
    
    return TransactionListView(searchText: $searchText)
        .modelContainer(container)
}
