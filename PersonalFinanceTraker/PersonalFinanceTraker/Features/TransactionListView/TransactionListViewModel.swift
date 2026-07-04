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

    var totalFilteredIncome: Decimal {
        filteredItems.filter { $0.amount > 0 }.reduce(.zero) { $0 + $1.amount }
    }

    var totalFilteredExpenses: Decimal {
        abs(filteredItems.filter { $0.amount < 0 }.reduce(.zero) { $0 + $1.amount })
    }

    var searchText: String = "" {
        didSet { doFilterItemBySearchText() }
    }
    var chartData: [ChartDataPoint] = []
    var selectedTimePeriod: TimePeriod = .month
    var transactionToEdit: TransactionModel? = nil

    private(set) var pendingDeletion: [TransactionModel] = []
    private var pendingDeletionTask: Task<Void, Never>?
    var showUndoBanner: Bool = false
    var deleteProgress: Double = 0.0

    let repo: ITransactionRepository

    private let dataService = ChartDataService()
    public let currencyService = CurrencyService()
    private var isLoaded = false
    var loadError: String? = nil
    var isLoading = false

    init(repo: ITransactionRepository) {
        self.repo = repo
    }

    func load() {
        guard !isLoaded else { return }
        isLoaded = true
        isLoading = true
        // ponytail: Task defers work to next run loop so view renders spinner before the 180ms block
        Task {
            self.fetchAndRefresh()
            self.isLoading = false
        }
    }

    func reload() {
        isLoaded = false
        load()
    }

    private func fetchAndRefresh() {
        do {
            transactions = try repo.fetchAll()
            doFilterItemBySearchText()  // triggers filteredItems.didSet → groupTransactions() + chartData
        } catch { loadError = "Failed to load transactions: \(error.localizedDescription)" }
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
        reload()
    }

    func update() {
        try? repo.update()
        reload()
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
        let grouped = Dictionary(grouping: filteredItems) { calendar.startOfDay(for: $0.timestamp) }
        // ponytail: sort Date keys directly — avoids O(n log n) calendar.startOfDay calls in comparator
        groupedItems = grouped
            .sorted { $0.key > $1.key }
            .map { (date, items) in
                (date.formattedForTransaction(), items.sorted { $0.timestamp > $1.timestamp })
            }
    }
    
    func delete(_ item: TransactionModel) {
        scheduleDeletion([item])
    }

    func deleteItemsFromSection(dayItems: [TransactionModel], offsets: IndexSet) {
        let items = offsets.compactMap { i -> TransactionModel? in
            guard i < dayItems.count else { return nil }
            return transactions.first { $0.id == dayItems[i].id }
        }
        guard !items.isEmpty else { return }
        scheduleDeletion(items)
    }

    private func scheduleDeletion(_ items: [TransactionModel]) {
        pendingDeletionTask?.cancel()
        pendingDeletion.append(contentsOf: items)
        let ids = Set(items.map(\.id))
        transactions.removeAll { ids.contains($0.id) }
        doFilterItemBySearchText()
        deleteProgress = 0.0
        showUndoBanner = true
        pendingDeletionTask = Task {
            let start = Date.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                deleteProgress = min(Date.now.timeIntervalSince(start) / 5.0, 1.0)
                if deleteProgress >= 1.0 { break }
            }
            guard !Task.isCancelled else { return }
            commitPendingDeletion()
        }
    }

    func commitPendingDeletion() {
        for item in pendingDeletion {
            try? repo.delete(item)
        }
        pendingDeletion = []
        pendingDeletionTask?.cancel()
        pendingDeletionTask = nil
        showUndoBanner = false
        deleteProgress = 0.0
    }

    func undoDelete() {
        pendingDeletionTask?.cancel()
        pendingDeletionTask = nil
        pendingDeletion = []
        showUndoBanner = false
        deleteProgress = 0.0
        reload()
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
        reload()
        if failCount > 0 {
            importError = "Failed to save \(failCount) of \(transactions.count) transaction(s). Check available storage and try again."
        }
    }

}
