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
            chartData = dataService.generateChartData(from: filteredItems, for: selectedTimePeriod, payCycleStartDay: AppSettings.storedStartDay)
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
                                                                       for: selectedTimePeriod,
                                                                       payCycleStartDay: AppSettings.storedStartDay)

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
                item.note.localizedStandardContains(searchText) ||
                item.amount.description.localizedStandardContains(searchText) ||
                item.category.localizedStandardContains(searchText)
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

    var currentPeriodLabel: String? {
        guard selectedTimePeriod == .month, AppSettings.storedStartDay != 1 else { return nil }
        let (start, _) = PayCycleService.currentFinancialMonth(startDay: AppSettings.storedStartDay)
        return "Since \(start.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// Generates a CSV export of all currently filtered transactions
    func exportCSV() -> String {
        return CSVExportService.generateCSV(from: transactions)
    }

    // MARK: - CSV Import

    var csvFile: CSVFile? = nil
    var columnMapping = ColumnMapping()
    var categoryResolution: [String: CategoryModel] = [:]
    var mappedRows: [MappedRow] = []
    var availableCategories: [CategoryModel] = []
    var showingImportFlow = false
    var importNavigationPath: [ImportStep] = []
    var importError: String? = nil
    var isLoadingCSV = false

    func loadCSVFile(from url: URL) {
        isLoadingCSV = true
        Task {
            do {
                // Parse file off the main thread — can be slow for large files
                let (file, mapping) = try await Task.detached(priority: .userInitiated) {
                    let f = try CSVImportService.read(from: url)
                    let m = CSVColumnMapper.autoDetect(from: f)
                    return (f, m)
                }.value
                isLoadingCSV = false
                csvFile = file
                columnMapping = mapping
                columnMapping.defaultCurrency = currencyService.baseCurrency
                // Let the outer catch surface any fetch failure rather than silently hiding it
                availableCategories = try repo.fetchCategories()
                categoryResolution = [:]
                importNavigationPath = []
                showingImportFlow = true
            } catch {
                isLoadingCSV = false
                importError = error.localizedDescription
            }
        }
    }

    /// Offloads per-row work (date parsing, Decimal conversion) to a background thread.
    /// CategoryModel re-resolution happens back on the MainActor after the task completes.
    func applyMapping() async {
        guard let file = csvFile else { return }
        let uuidResolution: [String: UUID] = categoryResolution.mapValues { $0.id }
        let mapping = columnMapping

        let rawRows = await Task.detached(priority: .userInitiated) {
            CSVColumnMapper.applyRaw(mapping: mapping, to: file, categoryResolution: uuidResolution)
        }.value

        // Re-resolve CategoryModel references on MainActor
        mappedRows = rawRows.map { raw in
            guard let data = raw.data else {
                return MappedRow(transaction: nil, error: raw.error, rowIndex: raw.rowIndex)
            }
            let categoryModel = data.resolvedCategoryUUID.flatMap { uuid in
                availableCategories.first { $0.id == uuid }
            }
            let transaction = TransactionModel(
                timestamp: data.timestamp,
                amount: data.amount,
                note: data.note,
                category: data.category,
                categoryModel: categoryModel,
                currencyCode: data.currencyCode
            )
            return MappedRow(transaction: transaction, error: nil, rowIndex: raw.rowIndex)
        }
    }

    func confirmImport(_ transactions: [TransactionModel]) {
        var failCount = 0
        for t in transactions {
            do {
                try repo.add(t)
            } catch {
                failCount += 1
            }
        }
        showingImportFlow = false
        load()
        if failCount > 0 {
            importError = "Failed to save \(failCount) of \(transactions.count) transaction(s). Check available storage and try again."
        }
    }

}
