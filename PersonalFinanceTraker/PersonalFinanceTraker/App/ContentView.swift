//
//  ContentView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import SwiftUI
import SwiftData
import Charts

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State var showingAddItemView: Bool = false
    @State var itemToEdit: TransactionModel? = nil
    @Query(sort: \TransactionModel.timestamp, order: .reverse) private var items: [TransactionModel]
    @State private var selectedTimePeriod: TimePeriod = .month
    
    // Services
    private let dateFormatter = DateFormattingService()
    private let chartDataService = ChartDataService()
    
    private var groupedItems: [(String, [TransactionModel])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
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
        items.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
    }
    
    private var totalExpenses: Decimal {
        items.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount }
    }
    
    private var chartData: [ChartDataPoint] {
        chartDataService.generateChartData(from: items, for: selectedTimePeriod)
    }
    
    var body: some View {
        NavigationSplitView {
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
                
                // Totals Summary Section
//                Section {
//                    FinancialSummaryCard(
//                        income: totalIncome,
//                        expenses: totalExpenses,
//                        currencyCode: "EUR"
//                    )
//                }
                
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: showAddTransaction) {
                        Label("Add Item", systemImage: "plus")
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
        } detail: {
            Text("Select an item")
        }
        .sheet(isPresented: $showingAddItemView) {
            NavigationStack {
                TransactionView()
                    .padding(.top, 32)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $itemToEdit) { item in
            NavigationStack {
                TransactionView(transaction: item)
                    .padding(.top, 32)
            }
            .presentationDetents([.medium])
        }
    }

    private func showAddTransaction() {
        withAnimation {
            showingAddItemView.toggle()
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

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
                try? modelContext.save()
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: TransactionModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    
    // Add sample data
    SampleData.populateModelContext(container.mainContext)
    
    return ContentView()
        .modelContainer(container)
}
