//
//  TransactionListViewModel.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 14/10/25.
//

import Foundation
import Combine

final class TransactionListViewModel: ObservableObject {
    @Published var transactions: [TransactionModel] = []
    @Published var filteredItems: [TransactionModel] = []
    @Published var groupedItems: [(String, [TransactionModel])] = []
    @Published var searchText: String = ""
    @Published var chartData: [ChartDataPoint] = []
    @Published var selectedTimePeriod: TimePeriod = .month
    @Published var transactionToEdit: TransactionModel? = nil
    
    private let repo: ITransactionRepository
    private var cancellables = Set<AnyCancellable>()
    
    private let dateFormatter = DateFormattingService()
    private let chartDataService = ChartDataService()
    
    init(repo: ITransactionRepository) {
        self.repo = repo
        self._searchText.projectedValue
            .sink { [weak self] searchText in
                self?.doFilterItemBySearchText()
            }
            .store(in: &cancellables)
        
        self._filteredItems.projectedValue.sink { [weak self] searchText in
            self?.groupTransactions()
            self?.chartData = self?.chartDataService.generateChartData(from: self?.filteredItems ?? [],
                                                                       for: self?.selectedTimePeriod ?? .month) ?? []
        }
        .store(in: &cancellables)
    }
    
    func load() {
        do {
            transactions = try repo.fetchAll()
            doFilterItemBySearchText()
            groupTransactions()
            chartData = chartDataService.generateChartData(from: filteredItems,
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
        return items.reduce(0) { $0 + $1.amount }
    }

}
