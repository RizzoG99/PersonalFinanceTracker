//
//  TransactionListViewModel.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 14/10/25.
//

import Foundation
import SwiftData

enum RecurrenceDeleteScope {
    case thisOnly
    case thisAndFuture
}

@Observable @MainActor
final class TransactionListViewModel {
    var transactions: [TransactionSnapshot] = []
    var hasNoTransactions: Bool { transactions.isEmpty }
    var filteredItems: [TransactionSnapshot] = [] {
        didSet {
            updateGroupedItems()
            recomputeDerivedFilterState()
            intersectSelectionWithVisible()
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
    /// Set instead of scheduling deletion when a single swiped-to-delete item belongs to a
    /// recurring series — the view prompts for "this transaction" vs. "this and future" scope.
    var pendingRecurrenceDeletion: TransactionSnapshot? = nil
    /// Exposed so tests can await debounced filtering instead of racing the 250ms delay
    @ObservationIgnored private(set) var searchDebounceTask: Task<Void, Never>?
    var showUndoBanner: Bool = false
    var deleteProgress: Double = 0.0
    var pendingUndoMessage: String = ""
    /// Non-nil marks the pending mutation as an *edit* (already persisted): timeout is a no-op,
    /// undo runs this closure. Nil marks a *delete*: timeout runs the repo.delete loop.
    @ObservationIgnored private var pendingRevert: (() async -> Void)?
    /// Handle to the in-flight bulk-edit apply / undo-revert Task so tests await instead of sleeping.
    @ObservationIgnored private(set) var bulkEditTask: Task<Void, Never>?

    // MARK: - Multi-select
    var isSelecting = false
    var selectedIDs: Set<PersistentIdentifier> = []

    var selectedSnapshots: [TransactionSnapshot] {
        transactions.filter { selectedIDs.contains($0.id) }
    }

    /// True when every currently visible row is selected (drives the Select All / Deselect All label).
    var allVisibleSelected: Bool {
        !filteredItems.isEmpty && filteredItems.allSatisfy { selectedIDs.contains($0.id) }
    }

    func toggleSelection(_ id: PersistentIdentifier) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    func selectAllVisible() {
        selectedIDs = Set(filteredItems.map(\.id))
    }

    func deselectAll() {
        selectedIDs.removeAll()
    }

    func exitSelection() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func intersectSelectionWithVisible() {
        guard !selectedIDs.isEmpty else { return }
        let visible = Set(filteredItems.map(\.id))
        selectedIDs.formIntersection(visible)
    }

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
            reload()
        } catch { print(error) }
    }

    func update(id: PersistentIdentifier, with input: TransactionInput) async {
        do {
            try await repo.update(id: id, with: input)
            reload()
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
        let items = filteredItems
        Task { [weak self] in
            let grouped = await Task.detached(priority: .userInitiated) { Self.group(items) }.value
            self?.groupedItems = grouped
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
        scheduleDeletionOrPromptRecurrence([item])
    }

    func deleteItemsFromSection(dayItems: [TransactionSnapshot], offsets: IndexSet) {
        let items = offsets.compactMap { i -> TransactionSnapshot? in
            guard i < dayItems.count else { return nil }
            return transactions.first { $0.id == dayItems[i].id }
        }
        guard !items.isEmpty else { return }
        scheduleDeletionOrPromptRecurrence(items)
    }

    /// Swiping a single recurring occurrence needs the same "this transaction" vs.
    /// "this and future" choice the edit sheet offers, rather than silently deleting just
    /// that one row and leaving the series running. Multi-item deletion has no UI entry point
    /// today (no multi-select mode), so that path only ever needs the plain delete below.
    private func scheduleDeletionOrPromptRecurrence(_ items: [TransactionSnapshot]) {
        if items.count == 1, items[0].recurrenceRuleId != nil {
            pendingRecurrenceDeletion = items[0]
            return
        }
        scheduleDeletion(items)
    }

    func applyRecurrenceDeletionScope(_ scope: RecurrenceDeleteScope) {
        guard let item = pendingRecurrenceDeletion else { return }
        pendingRecurrenceDeletion = nil
        Task {
            switch scope {
            case .thisOnly:
                try? await repo.delete(id: item.id)
            case .thisAndFuture:
                if let ruleId = item.recurrenceRuleId {
                    let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: item.timestamp) ?? item.timestamp
                    try? await repo.closeRecurrenceRule(id: ruleId, endDate: dayBefore)
                    try? await repo.deleteOccurrences(recurrenceRuleId: ruleId, from: item.timestamp)
                }
            }
            onDataChanged?()
            reload()
        }
    }

    private func scheduleDeletion(_ items: [TransactionSnapshot]) {
        // NOTE: deliberately does NOT flush a prior pending mutation.
        //  - delete→delete: appending to pendingDeletion is intentional batching (swipe two
        //    rows quickly → one combined banner); flushing would split it into two banners.
        //  - edit→delete: setting `pendingRevert = nil` below makes commitPending() take the
        //    delete branch, and the prior edit was already persisted — no leak, nothing to flush.
        // Only delete→edit leaks, and that is finalized in armUndo (the edit arm), not here.
        pendingDeletionTask?.cancel()
        pendingDeletion.append(contentsOf: items)
        let ids = Set(items.map(\.id))
        transactions.removeAll { ids.contains($0.id) }
        Task { await doFilterItemBySearchText() }
        pendingRevert = nil                                  // delete case
        pendingUndoMessage = String(localized: "\(pendingDeletion.count) transaction deleted")
        deleteProgress = 0.0
        showUndoBanner = true
        pendingDeletionTask = startUndoTimer()
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

    /// Arm the 5s undo banner for an already-applied edit. `revert` restores prior state on undo.
    /// `async` because it must FINALIZE any in-flight mutation before arming a new one —
    /// otherwise a pending delete (rows removed from `transactions`, not yet committed) would be
    /// abandoned when `pendingRevert` is set and `commitPending()` takes the edit branch.
    func armUndo(message: String, revert: @escaping () async -> Void) async {
        if showUndoBanner { await commitPending() }   // commit a prior delete / clear a prior edit
        pendingDeletionTask?.cancel()
        pendingUndoMessage = message
        pendingRevert = revert
        deleteProgress = 0.0
        showUndoBanner = true
        pendingDeletionTask = startUndoTimer()
    }

    /// Shared 5s progress timer, extracted from scheduleDeletion.
    private func startUndoTimer() -> Task<Void, Never> {
        Task {
            let start = Date.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                deleteProgress = min(Date.now.timeIntervalSince(start) / 5.0, 1.0)
                if deleteProgress >= 1.0 { break }
            }
            guard !Task.isCancelled else { return }
            await commitPending()
        }
    }

    /// Timeout finalizer. Branches on mutation kind (Gap 2): an edit's commit must NOT
    /// run the delete loop.
    func commitPending() async {
        if pendingRevert != nil {
            // Edit: write already persisted; just clear the banner.
            pendingRevert = nil
            pendingUndoMessage = ""
            showUndoBanner = false
            deleteProgress = 0.0
            pendingDeletionTask?.cancel()
            pendingDeletionTask = nil
        } else {
            await commitPendingDeletion()   // existing delete loop, unchanged
        }
    }

    /// Undo for either mutation kind.
    func undoPending() {
        pendingDeletionTask?.cancel()
        pendingDeletionTask = nil
        if let revert = pendingRevert {
            pendingRevert = nil
            pendingUndoMessage = ""
            showUndoBanner = false
            deleteProgress = 0.0
            bulkEditTask = Task { await revert(); onDataChanged?(); reload() }   // exposed so tests await, not sleep
        } else {
            undoDelete()   // existing delete-undo (reload restores uncommitted rows)
        }
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

    // MARK: - CSV Import

    var csvFile: CSVFile? = nil
    var xlsxWorkbook: XLSXWorkbook? = nil
    var columnMapping = ColumnMapping()
    var categoryResolutionSelections: [String: String] = [:]  // UUID strings or "__new__" sentinel
    var csvCategories: [String] = []                          // Unique CSV categories (computed once)
    var csvCategoryTypes: [String: TransactionType] = [:]      // Inferred type per CSV category
    var mappedRows: [MappedRow] = []
    var recurrenceSuggestions: [RecurrenceSuggestion] = []
    var selectedSuggestionIds: Set<UUID> = []
    var importedTransactionCount = 0
    var availableCategories: [CategorySnapshot] = []
    var showingImportFlow = false
    var importNavigationPath: [ImportStep] = []
    var importError: String? = nil
    var isLoadingImportFile = false
    var isImporting = false                                    // UI state during batch insert
    var hasAutoMappedCategories = false                        // Guard to prevent re-running autoMap on back-nav

    @ObservationIgnored var importProfileStore = ImportProfileStore()
    @ObservationIgnored private(set) var currentImportSignature: String? = nil
    @ObservationIgnored private var savedCategorySelections: [String: String]? = nil

    func loadCSVFile(from url: URL) {
        isLoadingImportFile = true
        Task {
            do {
                // Parse file off the main thread — can be slow for large files
                let (file, mapping) = try await Task.detached(priority: .userInitiated) {
                    let f = try CSVImportService.read(from: url)
                    let m = CSVColumnMapper.autoDetect(from: f)
                    return (f, m)
                }.value
                isLoadingImportFile = false
                csvFile = file
                columnMapping = mapping
                applyImportProfileIfAvailable(for: file)
                columnMapping.defaultCurrency = currencyService.baseCurrency
                // Let the outer catch surface any fetch failure rather than silently hiding it
                availableCategories = try await repo.fetchCategories()
                resetImportSelectionState()
                await presentImportFlowOrInform()
            } catch {
                isLoadingImportFile = false
                importError = error.localizedDescription
            }
        }
    }

    /// Runs dedup detection up front (requires a resolved date+amount mapping,
    /// which autoDetect/import profiles usually provide). If every row turns
    /// out to be a duplicate, informs the user instead of opening a wizard
    /// that dead-ends on a disabled "Import 0 Transactions" button.
    private func presentImportFlowOrInform() async {
        await applyMapping()
        if !mappedRows.isEmpty && mappedRows.allSatisfy(\.isDuplicate) {
            let n = mappedRows.count.formatted()
            cancelImport()
            importError = "All \(n) transactions in this file are already in the app — nothing new to import."
            return
        }
        showingImportFlow = true
    }

    /// Handle to the in-flight load so tests (and callers) can await completion
    @ObservationIgnored private(set) var loadExcelTask: Task<Void, Never>?

    func loadExcelFile(from url: URL) {
        isLoadingImportFile = true
        loadExcelTask = Task {
            do {
                let workbook = try await Task.detached(priority: .userInitiated) {
                    try XLSXWorkbook.read(from: url)
                }.value
                isLoadingImportFile = false
                availableCategories = try await repo.fetchCategories()
                resetImportSelectionState()

                if workbook.sheetNames.count == 1, let onlySheet = workbook.sheetNames.first {
                    try applySheet(onlySheet, of: workbook)
                    xlsxWorkbook = nil
                    await presentImportFlowOrInform()
                } else {
                    xlsxWorkbook = workbook
                    csvFile = nil
                    showingImportFlow = true
                }
            } catch {
                isLoadingImportFile = false
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
        applyImportProfileIfAvailable(for: file)
        columnMapping.defaultCurrency = currencyService.baseCurrency
    }

    /// Prefill the wizard from a previously saved profile for this file layout.
    private func applyImportProfileIfAvailable(for file: CSVFile) {
        let signature = ImportProfileStore.signature(
            headers: file.headers, delimiter: file.delimiter
        )
        currentImportSignature = signature
        guard let profile = importProfileStore.profile(for: signature) else { return }
        columnMapping = profile.mapping
        savedCategorySelections = profile.categorySelections
    }

    /// Called after csvCategories are computed; prefills selections that still
    /// point at an existing category. Unknown/deleted categories fall back to
    /// the normal auto-mapping flow.
    func applySavedCategorySelections() {
        guard let saved = savedCategorySelections else { return }
        let validIds = Set(availableCategories.map { $0.id.uuidString })
        for category in csvCategories {
            if let selection = saved[category], validIds.contains(selection) {
                categoryResolutionSelections[category] = selection
            }
        }
    }

    /// Test seam: savedCategorySelections is private because production code
    /// only sets it via applyImportProfileIfAvailable (which needs a CSVFile).
    func setSavedCategorySelectionsForTesting(_ selections: [String: String]?) {
        savedCategorySelections = selections
    }

    /// Resets per-file import selection state; shared by loadCSVFile and loadExcelFile
    /// so a newly loaded file always starts with a clean category-mapping slate.
    private func resetImportSelectionState() {
        categoryResolutionSelections = [:]
        csvCategories = []
        csvCategoryTypes = [:]
        recurrenceSuggestions = []
        selectedSuggestionIds = []
        importedTransactionCount = 0
        importNavigationPath = []
        hasAutoMappedCategories = false
        savedCategorySelections = nil
        currentImportSignature = nil
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
        recurrenceSuggestions = []
        selectedSuggestionIds = []
        importedTransactionCount = 0
        importNavigationPath = []
        hasAutoMappedCategories = false
        importError = nil
        isImporting = false
        savedCategorySelections = nil
        currentImportSignature = nil
    }

    // MARK: - Bulk actions

    /// Reconstruct a lossless input from a snapshot, optionally overriding amount or note.
    /// Always preserves category linkage; category changes build their input directly (below).
    private func input(from s: TransactionSnapshot,
                       amount: Decimal? = nil,
                       note: String? = nil) -> TransactionInput {
        TransactionInput(
            timestamp: s.timestamp,
            amount: amount ?? s.amount,
            note: note ?? s.note,
            category: s.category,
            currencyCode: s.currencyCode,
            goalId: s.goalId,
            categoryPersistentId: s.categoryId,
            recurrenceRuleId: s.recurrenceRuleId
        )
    }

    func bulkDelete() {
        let targets = selectedSnapshots
        guard !targets.isEmpty else { return }
        exitSelection()
        scheduleDeletion(targets)   // plain delete, no recurrence prompt (matches existing multi-delete path)
    }

    func bulkSetCategory(_ category: CategorySnapshot) {
        // A category is typed, and the app never mixes a category with a mismatched sign.
        // So applying a category flips each row's type to match: income category → positive
        // amount, expense category → negative. A categorized row is not a transfer, so its
        // goalId is cleared. (Undo restores the captured prior inputs, sign and goalId included.)
        let isIncome = category.transactionType == .income
        applyBulkEdit(message: { String(localized: "\($0) transactions updated") }) { s in
            let magnitude = abs(s.amount)
            return TransactionInput(
                timestamp: s.timestamp,
                amount: isIncome ? magnitude : -magnitude,
                note: s.note,
                category: category.name,
                currencyCode: s.currencyCode,
                goalId: nil,
                categoryPersistentId: category.persistentId,
                recurrenceRuleId: s.recurrenceRuleId
            )
        }
    }

    func bulkSetAmount(_ magnitude: Decimal) {
        applyBulkEdit(message: { String(localized: "\($0) transactions updated") }) { s in
            // Preserve sign: expenses stay negative, income positive.
            let signed = s.amount < 0 ? -abs(magnitude) : abs(magnitude)
            return self.input(from: s, amount: signed)
        }
    }

    func bulkSetNote(_ note: String) {
        applyBulkEdit(message: { String(localized: "\($0) transactions updated") }) { s in
            self.input(from: s, note: note)
        }
    }

    /// Shared edit driver: capture prior inputs, apply new inputs, arm the undo banner with a revert.
    /// Order matters: write edits → `await armUndo` (which finalizes any prior pending mutation) →
    /// reload. Reloading only after the flush avoids a transient reappear-then-vanish flicker of a
    /// prior delete's rows.
    private func applyBulkEdit(message: (Int) -> String,
                               newInput: @escaping (TransactionSnapshot) -> TransactionInput) {
        let targets = selectedSnapshots
        guard !targets.isEmpty else { return }
        let count = targets.count
        let prior: [(PersistentIdentifier, TransactionInput)] = targets.map { ($0.id, input(from: $0)) }
        let text = message(count)
        exitSelection()
        bulkEditTask = Task {
            // ponytail: loop update; add updateBatch only if it measurably lags
            for t in targets {
                try? await repo.update(id: t.id, with: newInput(t))
            }
            await armUndo(message: text) {
                for (id, input) in prior { try? await self.repo.update(id: id, with: input) }
            }
            onDataChanged?()
            reload()
        }
    }

    /// Offloads per-row work (date parsing, Decimal conversion) to a background thread.
    /// CategorySnapshot re-resolution and recurrence detection happen back on the MainActor after
    /// the task completes, so every import surface works from the same mapped preview.
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

        let existingRules = (try? await repo.fetchActiveRecurrenceRules()) ?? []
        recurrenceSuggestions = RecurrenceDetector.detect(
            in: mappedRows.compactMap(\.input),
            existingRules: existingRules
        )
        selectedSuggestionIds = Set(recurrenceSuggestions.map(\.id))
    }

    private static func duplicateKey(timestamp: Date, amount: Decimal, note: String) -> String {
        "\(timestamp.timeIntervalSince1970)_\(amount)_\(note)"
    }

    private static func duplicateKey(_ t: TransactionSnapshot) -> String {
        duplicateKey(timestamp: t.timestamp, amount: t.amount, note: t.note)
    }

    @ObservationIgnored private(set) var confirmImportTask: Task<Void, Never>?

    /// - Parameter addingRecurrenceRules: iPad reviews the detected recurrences *before* confirming
    ///   (third segment of the wizard), so the rules are written as part of the same import and
    ///   there is no follow-up step. iPhone leaves this false and reviews them afterwards.
    func confirmImport(_ inputs: [TransactionInput], addingRecurrenceRules: Bool = false) {
        confirmImportTask = Task {   // exposed so tests await, not sleep
            importedTransactionCount = 0
            // Cleared up front so the `importError == nil` checks below only ever see a message
            // this run produced.
            importError = nil

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

            // Persist the profile so the next import of this layout is prefilled.
            // "__new__" selections are stored as the just-created category's UUID.
            if let signature = currentImportSignature {
                var resolvedSelections = categoryResolutionSelections
                for (csvCatName, selection) in resolvedSelections where selection == "__new__" {
                    let createdName = csvCatName.removingLeadingEmoji
                        .trimmingCharacters(in: .whitespaces)
                    if let created = updatedCategories.first(where: { $0.name == createdName }) {
                        resolvedSelections[csvCatName] = created.id.uuidString
                    }
                }
                importProfileStore.save(
                    ImportProfile(mapping: columnMapping, categorySelections: resolvedSelections),
                    for: signature
                )
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

            // Step 8: Continue to the candidates detected from this mapped import. Detection has
            // already happened before confirmation, so iPhone and iPad review the same rows.
            let importedCount = toInsert.count - failCount
            importedTransactionCount = importedCount

            // The rules the user left checked in the preview step are written here, before the
            // teardown below clears the suggestions.
            var addedRuleCount = 0
            if addingRecurrenceRules && failCount == 0 {
                addedRuleCount = await persistSelectedRecurrenceRules()
            }

            // If import succeeded and there are recurrence suggestions, keep the sheet open and navigate to suggestions screen
            // Otherwise, dismiss the import flow with the standard summary message
            if !addingRecurrenceRules && failCount == 0 && !recurrenceSuggestions.isEmpty {
                // Recurrence suggestions available: navigate to suggestion screen without dismissing sheet
                onDataChanged?()
                reload()
                importNavigationPath.append(.recurringSuggestions)
            } else {
                // No suggestions: dismiss the import flow with summary (existing behavior)
                showingImportFlow = false
                onDataChanged?()
                reload()

                // Build summary message (show for both success and partial failures). A rule-save
                // failure already put a message here; it is the more specific one, so it wins.
                if importError == nil, importedCount > 0 || failCount > 0 || skippedDuplicates > 0 {
                    // Collected as sentences and joined. The `\(n == 1 ? "" : "s")` this replaces
                    // built the plural in Swift, which can only ever be right for English —
                    // Italian needs transazione/transazioni. The catalog's plural variations pick
                    // the form per language.
                    var parts: [String] = []
                    if importedCount > 0 {
                        parts.append(String(localized: "Imported \(importedCount) transactions."))
                    }
                    if skippedDuplicates > 0 {
                        parts.append(String(localized: "Skipped \(skippedDuplicates) duplicates."))
                    }
                    if failCount > 0 {
                        parts.append(String(localized: "Failed to save \(failCount) of \(toInsert.count). Check available storage and try again."))
                    }
                    if addedRuleCount > 0 {
                        parts.append(String(localized: "Added \(addedRuleCount) recurring transactions."))
                    }
                    importError = parts.joined(separator: " ")
                }
            }
        }
    }

    /// Create and persist recurrence rules for all selected suggestions.
    /// The transactions from the import already exist; nextDate is in the future,
    /// so RecurrenceMaterializationService will pick them up naturally at the next launch.
    /// Do NOT materialize occurrences here — that would create a duplicate of the first
    /// occurrence, which is already in the database from the import.
    func addSelectedRecurrenceRules() async {
        await persistSelectedRecurrenceRules()
        // A save failure leaves importError set, and cancelImport() clears it — the flow would
        // vanish with no explanation. Stay put so the alert has something to show.
        guard importError == nil else { return }
        cancelImport()
    }

    /// Writes the checked suggestions and returns how many were created. Does not dismiss anything —
    /// `confirmImport` calls it mid-flight and still needs the flow state afterwards.
    @discardableResult
    private func persistSelectedRecurrenceRules() async -> Int {
        var added = 0
        for suggestion in recurrenceSuggestions where selectedSuggestionIds.contains(suggestion.id) {
            let ruleInput = RecurrenceRuleInput(
                frequency: suggestion.frequency,
                interval: suggestion.interval,
                startDate: suggestion.nextDate,
                endDate: nil,
                lastMaterializedDate: nil,
                amount: suggestion.amount,
                note: suggestion.note,
                category: suggestion.category,
                currencyCode: suggestion.currencyCode,
                categoryPersistentId: suggestion.categoryPersistentId
            )
            do {
                try await repo.addRecurrenceRule(ruleInput)
                added += 1
            } catch {
                importError = String(localized: "Failed to save recurrence rule: \(error.localizedDescription)")
                return added
            }
        }
        return added
    }
}
