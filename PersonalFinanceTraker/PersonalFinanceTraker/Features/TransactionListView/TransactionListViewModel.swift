//
//  TransactionListViewModel.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 14/10/25.
//

import Foundation

@Observable @MainActor
final class TransactionListViewModel {
    var transactions: [TransactionModel] = []
    var filteredItems: [TransactionModel] = [] {
        didSet {
            groupTransactions()
            chartData = dataService.generateChartData(from: filteredItems, for: selectedTimePeriod)
        }
    }
    var groupedItems: [(String, [TransactionModel])] = []
    var searchText: String = "" {
        didSet { doFilterItemBySearchText() }
    }
    var chartData: [ChartDataPoint] = []
    var selectedTimePeriod: TimePeriod = .month
    var transactionToEdit: TransactionModel? = nil

    let repo: ITransactionRepository

    private let dateFormatter = DateFormattingService()
    private let dataService = ChartDataService()
    public let currencyService = CurrencyService()

    init(repo: ITransactionRepository) {
        self.repo = repo
    }
    
    func load() {
        do {
            transactions = try repo.fetchAll()
            doFilterItemBySearchText()
            groupTransactions()
            chartData = dataService.generateChartData(from: filteredItems,
                                                                       for: selectedTimePeriod)

        } catch { print(error) }
    }
    
    func add(date: Date, amount: Decimal, note: String, category: String) {
        let item = TransactionModel(
            timestamp: date,
            amount: amount,
            note: note,
            category: category
        )
        add(item)
    }
    
    func add(_ item: TransactionModel) {
        try? repo.add(item)
        load()
    }
    
    func update() {
        try? repo.update()
        load()
    }
    
    private func doFilterItemBySearchText() {
        if searchText.isEmpty {
            self.filteredItems = transactions
        } else {
            self.filteredItems = transactions.filter { item in
                item.note.localizedCaseInsensitiveContains(searchText) ||
                item.amount.description.localizedCaseInsensitiveContains(searchText) ||
                item.category.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private func groupTransactions() {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: self.filteredItems) { item in
            calendar.startOfDay(for: item.timestamp)
        }
        
        self.groupedItems = grouped.map { (date, items) in
            (dateFormatter.formatTransactionDate(date), items.sorted { $0.timestamp > $1.timestamp })
        }.sorted { first, second in
            // Sort sections by date (newest first)
            let firstDate = calendar.startOfDay(for: first.1.first?.timestamp ?? Date())
            let secondDate = calendar.startOfDay(for: second.1.first?.timestamp ?? Date())
            return firstDate > secondDate
        }
    }
    
    func deleteItemsFromSection(dayItems: [TransactionModel], offsets: IndexSet) {
        for index in offsets {
            if let itemToDelete = transactions.first(where: { $0.id == dayItems[index].id }) {
                do {
                    try repo.delete(itemToDelete)
                } catch {
                    print(error.localizedDescription)
                }
            }
        }
        // Reload data to reflect the changes
        load()
    }
    
    func totalForDate(items: [TransactionModel]) -> Decimal {
        return items.reduce(0) { total, item in
            let convertedAmount = currencyService.convertToBase(item.amount, from: item.currencyCode)
            return total + convertedAmount
        }
    }

    func clearSearch() {
        self.searchText = ""
    }

    /// Generates a CSV export of all currently filtered transactions
    func exportCSV() -> String {
        return CSVExportService.generateCSV(from: transactions)
    }

}
