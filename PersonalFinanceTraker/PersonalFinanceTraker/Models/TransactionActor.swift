//  TransactionActor.swift
//  PersonalFinanceTraker

import Foundation
import SwiftData

@ModelActor
actor TransactionActor: ITransactionRepository {
    /// A session-scoped value cache shared by Activity, widgets, backups, and dashboard work.
    /// `TransactionSnapshot` is immutable and `Sendable`, so returning this array across actor
    /// boundaries does not expose live SwiftData models.
    private var cachedTransactionSnapshots: [TransactionSnapshot]?
    private var cachedSnapshotRevision: UInt64?
    /// Actor-local generation also identifies materializations in traces/tests without
    /// conflating this repository with shell/widget work in the same test host process.
    private(set) var snapshotMaterializationGeneration: UInt64 = 0

    /// Allows the few legacy flows that write through a `ModelContext` directly to keep this
    /// actor-owned cache coherent. Normal transaction mutations clear it internally below.
    func invalidateTransactionSnapshotCache() {
        TransactionSnapshotRevision.shared.advance(for: modelContainer)
        cachedTransactionSnapshots = nil
        cachedSnapshotRevision = nil
        PerformanceAuditRecorder.event("TransactionActor.fetchAll.cache.invalidated")
    }

    // MARK: Transactions

    func fetchAll() async throws -> [TransactionSnapshot] {
        let measurement = PerformanceAuditRecorder.begin("TransactionActor.fetchAll")
        let revisions = TransactionSnapshotRevision.shared
        let revision = revisions.revision(for: modelContainer)
        if let cachedTransactionSnapshots, cachedSnapshotRevision == revision {
            PerformanceAuditRecorder.event("TransactionActor.fetchAll.cache")
            PerformanceAuditRecorder.end(
                measurement,
                metadata: "items=\(cachedTransactionSnapshots.count) source=cache revision=\(revision) generation=\(snapshotMaterializationGeneration)"
            )
            return cachedTransactionSnapshots
        }

        PerformanceAuditRecorder.event("TransactionActor.fetchAll.store")
        let desc = FetchDescriptor<TransactionModel>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        do {
            let readRevision = revisions.revision(for: modelContainer)
            // A long-lived write context may have registered values from before a save
            // in another context. Each materialization uses a fresh, actor-confined read
            // context; only immutable Sendable values survive it.
            let readContext = ModelContext(modelContainer)
            let fetchMeasurement = PerformanceAuditRecorder.begin("TransactionActor.store.fetch", metadata: "revision=\(readRevision)")
            let models: [TransactionModel]
            do {
                models = try readContext.fetch(desc)
                PerformanceAuditRecorder.end(fetchMeasurement, metadata: "items=\(models.count)")
            } catch {
                PerformanceAuditRecorder.end(fetchMeasurement, outcome: .failed)
                throw error
            }
            let mapping = PerformanceAuditRecorder.begin("TransactionActor.snapshots.map", metadata: "items=\(models.count) revision=\(readRevision)")
            let transactions = models.map(TransactionSnapshot.init)
            PerformanceAuditRecorder.end(mapping)
            // A save landed mid-read: hand back this read but don't cache it; the next call
            // re-reads. Retrying here could spin for as long as another context keeps saving.
            if readRevision == revisions.revision(for: modelContainer) {
                cachedTransactionSnapshots = transactions
                cachedSnapshotRevision = readRevision
                snapshotMaterializationGeneration += 1
            } else {
                PerformanceAuditRecorder.event("TransactionActor.snapshots.superseded")
            }
            PerformanceAuditRecorder.end(
                measurement,
                metadata: "items=\(transactions.count) source=store revision=\(readRevision) generation=\(snapshotMaterializationGeneration)"
            )
            return transactions
        } catch {
            PerformanceAuditRecorder.end(measurement, outcome: .failed)
            throw error
        }
    }

    func add(_ input: TransactionInput) async throws {
        let model = TransactionModel(
            timestamp: input.timestamp,
            amount: input.amount,
            note: input.note,
            category: input.category,
            currencyCode: input.currencyCode,
            goalId: input.goalId,
            travelId: input.travelId,
            recurrenceRuleId: input.recurrenceRuleId
        )
        if let pid = input.categoryPersistentId,
           let cat = modelContext.model(for: pid) as? CategoryModel {
            model.categoryModel = cat
        }
        modelContext.insert(model)
        try modelContext.save()
        invalidateTransactionSnapshotCache()
        await refreshSafeToSpendWidgetSnapshot()
    }

    func addBatch(_ inputs: [TransactionInput]) async throws {
        // Insert all models first, then save once to minimize round-trips
        for input in inputs {
            let model = TransactionModel(
                timestamp: input.timestamp,
                amount: input.amount,
                note: input.note,
                category: input.category,
                currencyCode: input.currencyCode,
                goalId: input.goalId,
                travelId: input.travelId,
                recurrenceRuleId: input.recurrenceRuleId
            )
            if let pid = input.categoryPersistentId,
               let cat = modelContext.model(for: pid) as? CategoryModel {
                model.categoryModel = cat
            }
            modelContext.insert(model)
        }
        try modelContext.save()
        invalidateTransactionSnapshotCache()
        await refreshSafeToSpendWidgetSnapshot()
    }

    func delete(id: PersistentIdentifier) async throws {
        guard let model = modelContext.model(for: id) as? TransactionModel else { return }
        modelContext.delete(model)
        try modelContext.save()
        invalidateTransactionSnapshotCache()
        await refreshSafeToSpendWidgetSnapshot()
    }

    func deleteAllTransactions() async throws {
        let all = try modelContext.fetch(FetchDescriptor<TransactionModel>())
        for model in all {
            modelContext.delete(model)
        }
        try modelContext.save()
        invalidateTransactionSnapshotCache()
        await refreshSafeToSpendWidgetSnapshot()
    }

    func update(id: PersistentIdentifier, with input: TransactionInput) async throws {
        guard let model = modelContext.model(for: id) as? TransactionModel else { return }
        apply(input, to: model, in: modelContext)
        try modelContext.save()
        invalidateTransactionSnapshotCache()
        await refreshSafeToSpendWidgetSnapshot()
    }

    func updateBatch(_ updates: [TransactionUpdate]) async {
        await updateBatch(updates, saving: { try $0.save() })
    }

    /// The save seam lets tests fail the real persistence path without replacing the actor.
    /// Uses the actor's long-lived context, so its other mutations never act on stale copies of
    /// these rows. Rollback stays scoped to this batch: every actor method saves before it
    /// returns, and nothing here suspends before the flush.
    func updateBatch(_ updates: [TransactionUpdate],
                     saving save: @Sendable (ModelContext) throws -> Void) async {
        guard !updates.isEmpty else { return }
        let context = modelContext
        var saved = false
        do {
            for update in updates { try apply(update, in: context) }
            if context.hasChanges {
                try save(context)
                saved = true
            }
        } catch {
            // Preserve best-effort bulk semantics rather than changing to all-or-nothing.
            // Roll back the failed batch before retrying each row independently; a failed
            // row must not leak into a later successful row's save or the widget snapshot.
            context.rollback()
            for update in updates {
                do {
                    try apply(update, in: context)
                    if context.hasChanges {
                        try save(context)
                        saved = true
                    }
                } catch {
                    context.rollback()
                }
            }
        }
        guard saved else { return }
        invalidateTransactionSnapshotCache()
        await refreshSafeToSpendWidgetSnapshot()
    }

    private func apply(_ update: TransactionUpdate, in context: ModelContext) throws {
        let id = update.id
        var descriptor = FetchDescriptor<TransactionModel>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        guard let model = try context.fetch(descriptor).first else { return }
        apply(update.input, to: model, in: context)
    }

    private func apply(_ input: TransactionInput, to model: TransactionModel, in context: ModelContext) {
        model.timestamp = input.timestamp
        model.amount = input.amount
        model.note = input.note
        model.category = input.category
        model.currencyCode = input.currencyCode
        model.goalId = input.goalId
        model.travelId = input.travelId
        if let pid = input.categoryPersistentId,
           let cat = context.model(for: pid) as? CategoryModel {
            model.categoryModel = cat
        } else {
            model.categoryModel = nil
        }
    }

    // MARK: Recurrence rules

    func addRecurrenceRule(_ input: RecurrenceRuleInput) async throws {
        let rule = RecurrenceRule(
            id: input.id,
            frequency: input.frequency,
            interval: input.interval,
            startDate: input.startDate,
            endDate: input.endDate,
            lastMaterializedDate: input.lastMaterializedDate,
            autoRecord: input.autoRecord,
            amount: input.amount,
            note: input.note,
            category: input.category,
            currencyCode: input.currencyCode,
            goalId: input.goalId
        )
        if let pid = input.categoryPersistentId,
           let cat = modelContext.model(for: pid) as? CategoryModel {
            rule.categoryModel = cat
        }
        modelContext.insert(rule)
        try modelContext.save()
        await refreshSafeToSpendWidgetSnapshot()
    }

    /// Moves a forecast-only rule's "paid through" cursor (#188) — after a real payment matched,
    /// or when the user says they still pay a missed one. `amount` replaces the template so a
    /// variable bill forecasts its latest value.
    func advanceRecurrenceRule(id: UUID, cursor: Date, amount: Decimal?) async throws {
        var desc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        guard let rule = try modelContext.fetch(desc).first else { return }
        rule.lastMaterializedDate = cursor
        if let amount { rule.amount = amount }
        try modelContext.save()
        await refreshSafeToSpendWidgetSnapshot()
    }

    func fetchActiveRecurrenceRules() async throws -> [RecurrenceRuleSnapshot] {
        let today = Calendar.current.startOfDay(for: .now)
        let all = try modelContext.fetch(FetchDescriptor<RecurrenceRule>())
        return all.filter { $0.isActive(asOf: today) }.map(RecurrenceRuleSnapshot.init)
    }

    func fetchAllRecurrenceRules() async throws -> [RecurrenceRuleSnapshot] {
        let all = try modelContext.fetch(FetchDescriptor<RecurrenceRule>())
        return all.map(RecurrenceRuleSnapshot.init)
    }

    func fetchRecurrenceRule(id: UUID) async throws -> RecurrenceRuleSnapshot? {
        var desc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        return try modelContext.fetch(desc).first.map(RecurrenceRuleSnapshot.init)
    }

    func updateRecurrenceRule(id: UUID, with input: RecurrenceRuleInput) async throws {
        var desc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        guard let rule = try modelContext.fetch(desc).first else { return }
        rule.amount = input.amount
        rule.note = input.note
        rule.category = input.category
        rule.currencyCode = input.currencyCode
        rule.goalId = input.goalId
        if let pid = input.categoryPersistentId,
           let cat = modelContext.model(for: pid) as? CategoryModel {
            rule.categoryModel = cat
        } else {
            rule.categoryModel = nil
        }
        try modelContext.save()
        await refreshSafeToSpendWidgetSnapshot()
    }

    func closeRecurrenceRule(id: UUID, endDate: Date) async throws {
        var desc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        guard let rule = try modelContext.fetch(desc).first else { return }
        rule.endDate = endDate
        try modelContext.save()
        await refreshSafeToSpendWidgetSnapshot()
    }

    /// Deletes already-materialized rows for this rule at/after `cutoffDate` (not "future"
    /// rows in the un-materialized sense — every row in the table is materialized). Used to
    /// wipe out rows created under an old template so the next materialize pass regenerates
    /// them under the new one; see the re-entrancy note on RecurrenceMaterializationService.
    func deleteOccurrences(recurrenceRuleId: UUID, from cutoffDate: Date) async throws {
        let rows = try modelContext.fetch(FetchDescriptor<TransactionModel>(
            predicate: #Predicate { $0.recurrenceRuleId == recurrenceRuleId && $0.timestamp >= cutoffDate }
        ))
        rows.forEach { modelContext.delete($0) }

        var ruleDesc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == recurrenceRuleId })
        ruleDesc.fetchLimit = 1
        if let rule = try modelContext.fetch(ruleDesc).first {
            // A conservative lower bound (not the exact prior occurrence) is enough: the
            // calculator only needs `since < nextDueOccurrence` to regenerate it correctly.
            rule.lastMaterializedDate = Calendar.current.date(byAdding: .day, value: -1, to: cutoffDate)
        }
        try modelContext.save()
        invalidateTransactionSnapshotCache()
        await refreshSafeToSpendWidgetSnapshot()
    }

    func materializeOccurrences(ruleId: UUID, inputs: [TransactionInput], newCursor: Date) async throws {
        guard !inputs.isEmpty else { return }
        for input in inputs {
            let model = TransactionModel(
                timestamp: input.timestamp,
                amount: input.amount,
                note: input.note,
                category: input.category,
                currencyCode: input.currencyCode,
                goalId: input.goalId,
                recurrenceRuleId: ruleId
            )
            if let pid = input.categoryPersistentId,
               let cat = modelContext.model(for: pid) as? CategoryModel {
                model.categoryModel = cat
            }
            modelContext.insert(model)
        }
        var ruleDesc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == ruleId })
        ruleDesc.fetchLimit = 1
        if let rule = try modelContext.fetch(ruleDesc).first {
            rule.lastMaterializedDate = newCursor
        }
        try modelContext.save()
        invalidateTransactionSnapshotCache()
        await refreshSafeToSpendWidgetSnapshot()
    }

    func deleteAllRecurrenceRules() async throws {
        let all = try modelContext.fetch(FetchDescriptor<RecurrenceRule>())
        for model in all {
            modelContext.delete(model)
        }
        try modelContext.save()
        await refreshSafeToSpendWidgetSnapshot()
    }

    // MARK: Categories

    /// V2 (#239): reruns the sweep once for categories renamed before renames carried their
    /// transactions along.
    static let categoryNameRepairKey = "didRepairImportedCategoryNamesV2"

    /// One-time repair for #232: imports used to store the CSV's category name in `category`
    /// while linking `categoryModel` to the mapped app category, so list, budgets and charts
    /// showed the old name. Walks each category's own transactions — unlinked rows are never
    /// loaded — and saves once. Idempotent, so an interrupted run simply repeats.
    /// - Returns: how many transactions and rules were rewritten.
    @discardableResult
    func repairImportedCategoryNames(defaults: UserDefaults = .standard) throws -> Int {
        guard !defaults.bool(forKey: Self.categoryNameRepairKey) else { return 0 }
        let fixed = try syncCategoryNames(of: modelContext.fetch(FetchDescriptor<CategoryModel>()))
        defaults.set(true, forKey: Self.categoryNameRepairKey)
        return fixed
    }

    /// Renames a category and rewrites the `category` copy on its transactions and rules in the
    /// same save (#239) — otherwise the list, budgets and charts split it in two, as in #232.
    /// Runs here, off the main thread: a category can own thousands of transactions.
    /// - Returns: how many transactions and rules were rewritten.
    @discardableResult
    func renameCategory(id: PersistentIdentifier, to name: String) throws -> Int {
        guard let category = modelContext.model(for: id) as? CategoryModel else { return 0 }
        category.name = name
        return try syncCategoryNames(of: [category])
    }

    /// Walks each category's own transactions through the inverse relationship — unlinked rows
    /// are never loaded — and saves once.
    private func syncCategoryNames(of categories: [CategoryModel]) throws -> Int {
        var fixed = 0
        for category in categories {
            for tx in category.transactions ?? [] where tx.category != category.name {
                tx.category = category.name
                fixed += 1
            }
        }
        // Rules carry their own copy and stamp it on every occurrence they materialize. No
        // inverse to walk from the category side, but there are only ever a handful of rules.
        let ids = Set(categories.map(\.persistentModelID))
        for rule in try modelContext.fetch(FetchDescriptor<RecurrenceRule>()) {
            if let model = rule.categoryModel, ids.contains(model.persistentModelID), rule.category != model.name {
                rule.category = model.name
                fixed += 1
            }
        }
        if modelContext.hasChanges { try modelContext.save() }
        return fixed
    }

    func fetchCategories() async throws -> [CategorySnapshot] {
        let desc = FetchDescriptor<CategoryModel>(sortBy: [SortDescriptor(\.name)])
        return try modelContext.fetch(desc).map(CategorySnapshot.init)
    }

    func addCategory(_ input: CategoryInput) async throws {
        let model = CategoryModel(
            name: input.name,
            systemImage: input.systemImage,
            type: TransactionType(rawValue: input.type) ?? .expense,
            colorToken: input.colorToken,
            monthlyBudget: input.monthlyBudget,
            currencyCode: input.currencyCode
        )
        modelContext.insert(model)
        try modelContext.save()
        invalidateTransactionSnapshotCache()
    }

    func deleteCategory(id: PersistentIdentifier) async throws {
        guard let model = modelContext.model(for: id) as? CategoryModel else { return }
        modelContext.delete(model)
        try modelContext.save()
        invalidateTransactionSnapshotCache()
    }

    // MARK: Travels

    func fetchTravels() async throws -> [TravelSnapshot] {
        let desc = FetchDescriptor<TravelModel>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try modelContext.fetch(desc).map(TravelSnapshot.init)
    }

    @discardableResult
    func addTravel(name: String, symbolName: String) async throws -> UUID {
        let model = TravelModel(name: name, symbolName: symbolName)
        modelContext.insert(model)
        try modelContext.save()
        return model.id
    }

    func updateTravel(id: UUID, name: String, symbolName: String) async throws {
        var desc = FetchDescriptor<TravelModel>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        guard let model = try modelContext.fetch(desc).first else { return }
        model.name = name
        model.symbolName = symbolName
        try modelContext.save()
    }

    /// Deletes the folder, never its contents: members are untagged and stay in the list.
    func deleteTravel(id: UUID) async throws {
        let members = try modelContext.fetch(
            FetchDescriptor<TransactionModel>(predicate: #Predicate { $0.travelId == id })
        )
        for member in members { member.travelId = nil }

        var desc = FetchDescriptor<TravelModel>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        if let model = try modelContext.fetch(desc).first {
            modelContext.delete(model)
        }
        try modelContext.save()
        invalidateTransactionSnapshotCache()
    }

    /// Replaces all travels, preserving ids so restored transactions stay linked.
    func replaceAllTravels(_ travels: [TravelSnapshot]) async throws {
        try modelContext.delete(model: TravelModel.self)
        for travel in travels {
            modelContext.insert(
                TravelModel(id: travel.id, name: travel.name, symbolName: travel.symbolName, createdAt: travel.createdAt)
            )
        }
        try modelContext.save()
    }

    /// Bulk-tags (or with `travelId: nil`, untags) the given transactions.
    func setTravel(_ travelId: UUID?, forIDs ids: [PersistentIdentifier]) async throws {
        for id in ids {
            guard let model = modelContext.model(for: id) as? TransactionModel else { continue }
            model.travelId = travelId
        }
        try modelContext.save()
        invalidateTransactionSnapshotCache()
    }

    // MARK: Goals

    func fetchGoals() async throws -> [GoalSnapshot] {
        let desc = FetchDescriptor<GoalModel>(sortBy: [SortDescriptor(\.createdAt)])
        return try modelContext.fetch(desc).map(GoalSnapshot.init)
    }

    func addGoal(_ input: GoalInput) async throws {
        let model = GoalModel(
            name: input.name,
            targetAmount: input.targetAmount,
            deadline: input.deadline,
            colorToken: input.colorToken,
            iconName: input.iconName
        )
        modelContext.insert(model)
        try modelContext.save()
    }

    func updateGoal(id: UUID, with input: GoalInput) async throws {
        var desc = FetchDescriptor<GoalModel>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        guard let model = try modelContext.fetch(desc).first else { return }
        model.name = input.name
        model.targetAmount = input.targetAmount
        model.deadline = input.deadline
        model.colorToken = input.colorToken
        model.iconName = input.iconName
        try modelContext.save()
    }

    func deleteGoal(id: UUID) async throws {
        var desc = FetchDescriptor<GoalModel>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        guard let model = try modelContext.fetch(desc).first else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    // MARK: Health snapshots

    func saveSnapshot(_ data: HealthScoreSnapshotData) async throws {
        let model = HealthScoreSnapshot(
            timestamp: data.timestamp,
            score: data.score,
            savingsScore: data.savingsScore,
            stabilityScore: data.stabilityScore,
            adherenceScore: data.adherenceScore,
            subscriptionScore: data.subscriptionScore
        )
        modelContext.insert(model)
        try modelContext.save()
    }

    func fetchSnapshots(limit: Int) async throws -> [HealthScoreSnapshotData] {
        var desc = FetchDescriptor<HealthScoreSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        desc.fetchLimit = limit
        return try modelContext.fetch(desc).map(HealthScoreSnapshotData.init)
    }

    // MARK: Receipt scan — learned merchant → category

    func fetchMerchantCategoryMappings() async throws -> [String: UUID] {
        let rows = try modelContext.fetch(FetchDescriptor<MerchantCategoryMapping>())
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.merchant, $0.categoryId) })
    }

    /// Upserts by the unique `merchant` key — a correction on a merchant already learned overwrites
    /// it rather than accumulating a duplicate row.
    func saveMerchantCategoryMapping(merchant: String, categoryId: UUID) async throws {
        var descriptor = FetchDescriptor<MerchantCategoryMapping>(
            predicate: #Predicate { $0.merchant == merchant }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.categoryId = categoryId
        } else {
            modelContext.insert(MerchantCategoryMapping(merchant: merchant, categoryId: categoryId))
        }
        try modelContext.save()
    }

    // MARK: Safe to Spend widget

    /// Recomputes the lightweight app-group snapshot after every mutation that affects
    /// cash flow. The app also invokes this when it launches or becomes active.
    func refreshSafeToSpendWidgetSnapshot() async {
        let measurement = PerformanceAuditRecorder.begin("SafeToSpend.refresh")
        guard let transactions = try? await fetchAll(),
              let rules = try? await fetchActiveRecurrenceRules()
        else {
            PerformanceAuditRecorder.end(measurement, outcome: .failed)
            return
        }
        let payCycleStartDay = await AppSettings.storedStartDay
        let bufferPercent = await AppSettings.storedBufferPercent
        SafeToSpendSnapshotUpdater.refresh(
            transactions: transactions,
            activeRules: rules,
            payCycleStartDay: payCycleStartDay,
            bufferPercent: bufferPercent
        )
        PerformanceAuditRecorder.end(
            measurement,
            metadata: "transactions=\(transactions.count) rules=\(rules.count)"
        )
    }
}

extension TransactionActor {
    // #Preview macro expansion can't see the @ModelActor-generated init; this hand-written factory is visible there
    static func make(_ container: ModelContainer) -> TransactionActor {
        TransactionActor(modelContainer: container)
    }

    /// Everything after a rename in the edit sheet (#239): carry the name onto its rows, tell
    /// the app, then back up. Restore relinks by name and takes the newest backup, so one
    /// with the old name would bring the rows back unlinked — hence the forced, fresh one.
    nonisolated static func renameAndBackUp(
        container: ModelContainer,
        id: PersistentIdentifier,
        to newName: String,
        signal: DataChangedSignal?,
        settings: BackupSchedulingSettings?,
        backupService: BackupService = BackupService()
    ) async {
        let actor = make(container)
        _ = try? await actor.renameCategory(id: id, to: newName)
        await MainActor.run { signal?.bump() }  // also refreshes widget/Siri templates
        guard let settings else { return }
        await MainActor.run { settings.lastBackupDate = nil }
        await BackupScheduler.runIfNeeded(repo: actor, settings: settings, backupService: backupService)
    }
}
