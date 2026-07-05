//
//  TransactionListViewModel.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 14/10/25.
//

import Foundation

@Observable @MainActor
final class TransactionListViewModel {
    var transactions: [TransactionSnapshot] = []
    var filteredItems: [TransactionSnapshot] = [] {
        didSet {
            updateGroupedItems()
            chartData = dataService.generateChartData(from: filteredItems, for: selectedTimePeriod, payCycleStartDay: AppSettings.storedStartDay)
        }
    }
    var groupedItems: [(String, [TransactionSnapshot])] = []

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
    var transactionToEdit: TransactionSnapshot? = nil

    private(set) var pendingDeletion: [TransactionSnapshot] = []
    private var pendingDeletionTask: Task<Void, Never>?
    var showUndoBanner: Bool = false
    var deleteProgress: Double = 0.0

    let repo: any ITransactionRepository

    private let dataService = ChartDataService()
    public let currencyService = CurrencyService()
    private var isLoaded = false

    init(repo: any ITransactionRepository) {
        self.repo = repo
    }

    func load() {
        guard !isLoaded else { return }
        isLoaded = true
        Task {
            await fetchAndRefresh()
        }
    }

    func reload() {
        isLoaded = false
        load()
    }

    private func fetchAndRefresh() async {
        do {
            transactions = try await repo.fetchAll()
            doFilterItemBySearchText()  // triggers filteredItems.didSet → updateGroupedItems() + chartData
        } catch { print(error) }
    }

    func add(_ input: TransactionInput) async {
        do {
            try await repo.add(input)
            await reload()
        } catch { print(error) }
    }

    func update(id: PersistentIdentifier, with input: TransactionInput) async {
        do {
            try await repo.update(id: id, with: input)
            await reload()
        } catch { print(error) }
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

    private func updateGroupedItems() {
        Task.detached(priority: .userInitiated) { [weak self] in
            let grouped = Self.group(self?.filteredItems ?? [])
            await MainActor.run {
                self?.groupedItems = grouped
            }
        }
    }

    nonisolated private static func group(_ items: [TransactionSnapshot]) -> [(String, [TransactionSnapshot])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.timestamp)
        }

        return grouped.map { (date, items) in
            (date.formattedForTransaction(), items.sorted { $0.timestamp > $1.timestamp })
        }.sorted { first, second in
            // Sort sections by date (newest first)
            let firstDate = calendar.startOfDay(for: first.1.first?.timestamp ?? Date())
            let secondDate = calendar.startOfDay(for: second.1.first?.timestamp ?? Date())
            return firstDate > secondDate
        }
    }

    func delete(_ item: TransactionSnapshot) {
        scheduleDeletion([item])
    }

    func deleteItemsFromSection(dayItems: [TransactionSnapshot], offsets: IndexSet) {
        let items = offsets.compactMap { i -> TransactionSnapshot? in
            guard i < dayItems.count else { return nil }
            return transactions.first { $0.id == dayItems[i].id }
        }
        guard !items.isEmpty else { return }
        scheduleDeletion(items)
    }

    private func scheduleDeletion(_ items: [TransactionSnapshot]) {
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
            await commitPendingDeletion()
        }
    }

    func commitPendingDeletion() async {
        var failedItems: [TransactionSnapshot] = []
        for item in pendingDeletion {
            do {
                try await repo.delete(id: item.id)
            } catch {
                failedItems.append(item)
            }
        }
        // Re-insert failed items and re-filter
        if !failedItems.isEmpty {
            transactions.append(contentsOf: failedItems)
            doFilterItemBySearchText()
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

    func totalForDate(items: [TransactionSnapshot]) -> Decimal {
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
    var categoryResolution: [String: CategorySnapshot] = [:]
    var mappedRows: [MappedRow] = []
    var availableCategories: [CategorySnapshot] = []
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
                availableCategories = try await repo.fetchCategories()
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
    /// CategorySnapshot re-resolution happens back on the MainActor after the task completes.
    func applyMapping() async {
        guard let file = csvFile else { return }
        let uuidResolution: [String: UUID] = categoryResolution.mapValues { $0.id }
        let mapping = columnMapping

        let rawRows = await Task.detached(priority: .userInitiated) {
            CSVColumnMapper.applyRaw(mapping: mapping, to: file, categoryResolution: uuidResolution)
        }.value

        // Re-resolve CategorySnapshot references on MainActor
        mappedRows = rawRows.map { raw in
            guard let data = raw.data else {
                return MappedRow(input: nil, error: raw.error, rowIndex: raw.rowIndex)
            }
            let _resolvedCategory = data.resolvedCategoryUUID.flatMap { uuid in
                availableCategories.first { $0.id == uuid }
            }
            let input = TransactionInput(
                timestamp: data.timestamp,
                amount: data.amount,
                note: data.note,
                category: data.category,
                currencyCode: data.currencyCode
            )
            return MappedRow(input: input, error: nil, rowIndex: raw.rowIndex)
        }
    }

    func confirmImport(_ inputs: [TransactionInput]) {
        var failCount = 0
        Task {
            for input in inputs {
                do {
                    try await repo.add(input)
                } catch {
                    failCount += 1
                }
            }
            showingImportFlow = false
            await reload()
            if failCount > 0 {
                importError = "Failed to save \(failCount) of \(inputs.count) transaction(s). Check available storage and try again."
            }
        }
    }

}
