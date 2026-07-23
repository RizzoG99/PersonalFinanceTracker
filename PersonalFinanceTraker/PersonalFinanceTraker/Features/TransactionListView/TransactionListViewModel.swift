//
//  TransactionListViewModel.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 14/10/25.
//

import Foundation
import SwiftData

@Observable @MainActor
final class TransactionListViewModel {
    var transactions: [TransactionSnapshot] = []
    var filteredItems: [TransactionSnapshot] = [] {
        didSet {
            updateGroupedItems()
            recomputeDerivedFilterState()
        }
    }
    var groupedItems: [(String, [TransactionSnapshot])] = []

    /// Category chip selection on the Activity screen; nil means "All"
    var selectedCategory: String? = nil {
        didSet { recomputeDerivedFilterState() }
    }

    /// Categories offered as filter chips, most-used first (stable within a data set).
    /// Computed once per `filteredItems`/`selectedCategory` change rather than per render —
    /// SwiftUI re-evaluates the Activity body several times per keystroke while searching.
    private(set) var filterCategories: [String] = []

    /// selectedCategory, ignored when it no longer exists in the current data (e.g. after a search)
    private(set) var effectiveCategory: String? = nil

    /// Totals always match the visible list (search + category filter); no period scoping
    private(set) var totalFilteredIncome: Decimal = .zero
    private(set) var totalFilteredExpenses: Decimal = .zero

    private func recomputeDerivedFilterState() {
        let counts = Dictionary(grouping: filteredItems, by: \.category).mapValues(\.count)
        filterCategories = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        effectiveCategory = selectedCategory.flatMap { filterCategories.contains($0) ? $0 : nil }

        let scoped: [TransactionSnapshot]
        if let category = effectiveCategory {
            scoped = filteredItems.filter { $0.category == category }
        } else {
            scoped = filteredItems
        }
        var income = Decimal.zero
        var expenses = Decimal.zero
        for item in scoped {
            if item.amount > 0 { income += item.amount } else { expenses += item.amount }
        }
        totalFilteredIncome = income
        totalFilteredExpenses = abs(expenses)
    }

    var searchText: String = "" {
        didSet {
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await doFilterItemBySearchText()
            }
        }
    }
    var filters = SearchFilters() {
        didSet { Task { await doFilterItemBySearchText() } }
    }
    var selectedTimePeriod: TimePeriod = .month
    var transactionToEdit: TransactionSnapshot? = nil

    private(set) var pendingDeletion: [TransactionSnapshot] = []
    private var pendingDeletionTask: Task<Void, Never>?
    /// Exposed so tests can await debounced filtering instead of racing the 250ms delay
    @ObservationIgnored private(set) var searchDebounceTask: Task<Void, Never>?
    var showUndoBanner: Bool = false
    var deleteProgress: Double = 0.0

    let repo: any ITransactionRepository
    /// Set by the owning view; notifies the app that persisted data changed
    @ObservationIgnored var onDataChanged: (() -> Void)?

    public let currencyService = CurrencyService()
    private var isLoaded = false

    init(repo: any ITransactionRepository) {
        self.repo = repo
    }

    /// Handle to the in-flight fetch so tests (and callers) can await completion
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?

    func load() {
        guard !isLoaded else { return }
        isLoaded = true
        loadTask = Task {
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
            await doFilterItemBySearchText()  // triggers filteredItems.didSet → updateGroupedItems() + chartData
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

    private func doFilterItemBySearchText() async {
        guard !searchText.isEmpty || filters.isActive else {
            // Fast path: no filtering needed
            self.filteredItems = transactions
            return
        }

        let searchText = searchText
        let filters = filters
        let transactions = transactions
        let filtered = await Task.detached(priority: .userInitiated) {
            let dateBounds = filters.resolvedDateBounds()
            return transactions.filter { item in
                let textMatch = searchText.isEmpty || (
                    item.note.localizedStandardContains(searchText) ||
                    item.amount.description.localizedStandardContains(searchText) ||
                    item.category.localizedStandardContains(searchText)
                )
                let filterMatch = filters.matches(item, dateBounds: dateBounds)
                return textMatch && filterMatch
            }
        }.value

        self.filteredItems = filtered
    }

    private func updateGroupedItems() {
        Task.detached(priority: .userInitiated) { [weak self, items = filteredItems] in
            let grouped = Self.group(items)
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
        Task { await doFilterItemBySearchText() }
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
            await doFilterItemBySearchText()
        }
        pendingDeletion = []
        pendingDeletionTask?.cancel()
        pendingDeletionTask = nil
        showUndoBanner = false
        deleteProgress = 0.0
        onDataChanged?()
    }

    func undoDelete() {
        pendingDeletionTask?.cancel()
        pendingDeletionTask = nil
        pendingDeletion = []
        showUndoBanner = false
        deleteProgress = 0.0
        reload()
    }

    func clearSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        self.searchText = ""
        self.filters = SearchFilters()
        Task { await doFilterItemBySearchText() }
    }

    var currentPeriodLabel: String? {
        let (start, end) = periodBounds
        guard start != end else { return nil }

        let startFormatted = start.formatted(.dateTime.month(.abbreviated).day())
        let endFormatted = end.formatted(.dateTime.month(.abbreviated).day())
        return "This period · \(startFormatted) – \(endFormatted)"
    }

    private var periodBounds: (start: Date, end: Date) {
        switch selectedTimePeriod {
        case .month:
            return PayCycleService.currentFinancialMonth(startDay: AppSettings.storedStartDay)
        case .week:
            let calendar = Calendar.current
            let now = Date.now
            let startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start: startDate, end: now)
        case .year:
            let calendar = Calendar.current
            let now = Date.now
            let startDate = calendar.date(byAdding: .day, value: -365, to: now) ?? now
            return (start: startDate, end: now)
        }
    }

    /// Generates a CSV export of all currently filtered transactions
    func exportCSV() -> String {
        return CSVExportService.generateCSV(from: transactions)
    }

    // MARK: - CSV Import

    var csvFile: CSVFile? = nil
    var xlsxWorkbook: XLSXWorkbook? = nil
    var columnMapping = ColumnMapping()
    var categoryResolutionSelections: [String: String] = [:]  // UUID strings or "__new__" sentinel
    var csvCategories: [String] = []                          // Unique CSV categories (computed once)
    var csvCategoryTypes: [String: TransactionType] = [:]      // Inferred type per CSV category
    var mappedRows: [MappedRow] = []
    var availableCategories: [CategorySnapshot] = []
    var showingImportFlow = false
    var importNavigationPath: [ImportStep] = []
    var importError: String? = nil
    var isLoadingCSV = false
    var isImporting = false                                    // UI state during batch insert
    var hasAutoMappedCategories = false                        // Guard to prevent re-running autoMap on back-nav

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
                categoryResolutionSelections = [:]
                csvCategories = []
                csvCategoryTypes = [:]
                importNavigationPath = []
                hasAutoMappedCategories = false
                showingImportFlow = true
            } catch {
                isLoadingCSV = false
                importError = error.localizedDescription
            }
        }
    }

    /// Handle to the in-flight load so tests (and callers) can await completion
    @ObservationIgnored private(set) var loadExcelTask: Task<Void, Never>?

    func loadExcelFile(from url: URL) {
        isLoadingCSV = true
        loadExcelTask = Task {
            do {
                let workbook = try await Task.detached(priority: .userInitiated) {
                    try XLSXWorkbook.read(from: url)
                }.value
                isLoadingCSV = false
                availableCategories = try await repo.fetchCategories()
                categoryResolutionSelections = [:]
                csvCategories = []
                csvCategoryTypes = [:]
                importNavigationPath = []
                hasAutoMappedCategories = false

                if workbook.sheetNames.count == 1, let onlySheet = workbook.sheetNames.first {
                    try applySheet(onlySheet, of: workbook)
                    xlsxWorkbook = nil
                } else {
                    xlsxWorkbook = workbook
                    csvFile = nil
                }
                showingImportFlow = true
            } catch {
                isLoadingCSV = false
                importError = error.localizedDescription
            }
        }
    }

    func selectSheet(_ name: String) {
        guard let workbook = xlsxWorkbook else { return }
        do {
            try applySheet(name, of: workbook)
            xlsxWorkbook = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func applySheet(_ name: String, of workbook: XLSXWorkbook) throws {
        let file = try workbook.csvFile(forSheet: name)
        csvFile = file
        columnMapping = CSVColumnMapper.autoDetect(from: file)
        columnMapping.defaultCurrency = currencyService.baseCurrency
    }

    /// Cancel the import flow and reset state
    func cancelImport() {
        showingImportFlow = false
        csvFile = nil
        xlsxWorkbook = nil
        columnMapping = ColumnMapping()
        categoryResolutionSelections = [:]
        csvCategories = []
        csvCategoryTypes = [:]
        mappedRows = []
        importNavigationPath = []
        hasAutoMappedCategories = false
        importError = nil
        isImporting = false
    }

    /// Offloads per-row work (date parsing, Decimal conversion) to a background thread.
    /// CategorySnapshot re-resolution happens back on the MainActor after the task completes.
    func applyMapping() async {
        guard let file = csvFile else { return }
        // Build UUID resolution only for existing categories; "__new__" entries will have nil UUID
        let uuidResolution: [String: UUID?] = categoryResolutionSelections.mapValues { sel in
            sel == "__new__" ? nil : UUID(uuidString: sel)
        }
        let mapping = columnMapping

        let rawRows = await Task.detached(priority: .userInitiated) {
            CSVColumnMapper.applyRaw(mapping: mapping, to: file, categoryResolution: uuidResolution)
        }.value

        // Build category lookup dictionary once to avoid O(N*M) linear searches
        // ponytail: category lookup optimization
        let categoryById: [UUID: CategorySnapshot] = Dictionary(
            uniqueKeysWithValues: availableCategories.map { ($0.id, $0) }
        )

        // Mark rows that already exist in the store so the preview shows them
        // as duplicates instead of surprising the user at confirm time
        let existingKeys = (try? await repo.fetchAll()).map { Set($0.map(Self.duplicateKey)) } ?? []

        // Re-resolve CategorySnapshot references on MainActor
        mappedRows = rawRows.map { raw in
            guard let data = raw.data else {
                return MappedRow(input: nil, error: raw.error, rowIndex: raw.rowIndex)
            }
            let resolvedCategory = data.resolvedCategoryUUID.flatMap { categoryById[$0] }
            let input = TransactionInput(
                timestamp: data.timestamp,
                amount: data.amount,
                note: data.note,
                category: data.category,
                currencyCode: data.currencyCode,
                categoryPersistentId: resolvedCategory?.persistentId
            )
            let isDuplicate = existingKeys.contains(
                Self.duplicateKey(timestamp: data.timestamp, amount: data.amount, note: data.note)
            )
            return MappedRow(input: input, error: nil, rowIndex: raw.rowIndex, isDuplicate: isDuplicate)
        }
    }

    private static func duplicateKey(timestamp: Date, amount: Decimal, note: String) -> String {
        "\(timestamp.timeIntervalSince1970)_\(amount)_\(note)"
    }

    private static func duplicateKey(_ t: TransactionSnapshot) -> String {
        duplicateKey(timestamp: t.timestamp, amount: t.amount, note: t.note)
    }

    func confirmImport(_ inputs: [TransactionInput]) {
        Task {
            // Step 1: Create any new categories that need to be created
            var newCategoryPersistentIds: [String: PersistentIdentifier] = [:]
            for (csvCatName, selection) in categoryResolutionSelections {
                guard selection == "__new__" else { continue }
                let type = csvCategoryTypes[csvCatName] ?? .expense
                let categoryInput = CategoryInput(
                    name: csvCatName.removingLeadingEmoji.trimmingCharacters(in: .whitespaces),
                    systemImage: "tag",
                    type: type.rawValue,
                    colorToken: "categoryIndigo",
                    monthlyBudget: nil,
                    currencyCode: currencyService.baseCurrency
                )
                do {
                    try await repo.addCategory(categoryInput)
                } catch {
                    importError = "Failed to create category '\(csvCatName)': \(error.localizedDescription)"
                    showingImportFlow = false
                    return
                }
            }

            // Step 2: Fetch updated categories to get persistentIds for new categories
            let updatedCategories: [CategorySnapshot]
            do {
                updatedCategories = try await repo.fetchCategories()
            } catch {
                importError = "Failed to fetch updated categories: \(error.localizedDescription)"
                showingImportFlow = false
                return
            }

            // Step 3: Map CSV category names to persistentIds for newly created categories
            for (csvCatName, selection) in categoryResolutionSelections {
                guard selection == "__new__" else { continue }
                let createdName = csvCatName.removingLeadingEmoji.trimmingCharacters(in: .whitespaces)
                if let catSnapshot = updatedCategories.first(where: { $0.name == createdName }) {
                    newCategoryPersistentIds[csvCatName] = catSnapshot.persistentId
                }
            }

            // Step 4: Update transaction inputs to link to new categories
            var updatedInputs = inputs
            for i in updatedInputs.indices {
                if updatedInputs[i].categoryPersistentId == nil,
                   let persistentId = newCategoryPersistentIds[updatedInputs[i].category] {
                    updatedInputs[i] = TransactionInput(
                        timestamp: updatedInputs[i].timestamp,
                        amount: updatedInputs[i].amount,
                        note: updatedInputs[i].note,
                        category: updatedInputs[i].category,
                        currencyCode: updatedInputs[i].currencyCode,
                        categoryPersistentId: persistentId
                    )
                }
            }

            // Step 5: Fetch existing transactions once to detect duplicates
            let existing: [TransactionSnapshot]
            do {
                existing = try await repo.fetchAll()
            } catch {
                importError = "Failed to fetch existing transactions: \(error.localizedDescription)"
                showingImportFlow = false
                return
            }

            // Step 6: Filter duplicates and prepare batch insert
            // Build Set for O(1) duplicate detection instead of O(N*M) contains checks
            // ponytail: O(N) duplicate detection with Set
            let existingKeys = Set(existing.map(Self.duplicateKey))
            var toInsert: [TransactionInput] = []
            var skippedDuplicates = 0
            for input in updatedInputs {
                let key = Self.duplicateKey(timestamp: input.timestamp, amount: input.amount, note: input.note)
                if existingKeys.contains(key) {
                    skippedDuplicates += 1
                } else {
                    toInsert.append(input)
                }
            }

            // Step 7: Batch insert with UI feedback
            isImporting = true
            defer { isImporting = false }
            var failCount = 0
            do {
                try await repo.addBatch(toInsert)
            } catch {
                failCount = toInsert.count  // All failed in batch
            }

            showingImportFlow = false
            onDataChanged?()
            reload()

            // Build summary message (show for both success and partial failures)
            let importedCount = toInsert.count - failCount
            if importedCount > 0 || failCount > 0 || skippedDuplicates > 0 {
                var summary = ""
                if importedCount > 0 {
                    summary += "Imported \(importedCount) transaction\(importedCount == 1 ? "" : "s")."
                }
                if skippedDuplicates > 0 {
                    if !summary.isEmpty { summary += " " }
                    summary += "Skipped \(skippedDuplicates) duplicate\(skippedDuplicates == 1 ? "" : "s")."
                }
                if failCount > 0 {
                    if !summary.isEmpty { summary += " " }
                    summary += "Failed to save \(failCount) of \(toInsert.count). Check available storage and try again."
                }
                importError = summary
            }
        }
    }

}
