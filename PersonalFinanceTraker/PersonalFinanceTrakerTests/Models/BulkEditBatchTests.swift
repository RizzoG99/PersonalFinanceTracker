import Foundation
import SwiftData
import Testing
@testable import PersonalFinanceTraker

@Suite(.serialized)
@MainActor
struct BulkEditBatchTests {
    private enum SaveFailure: Error { case injected }

    private func fixture() throws -> ModelContainer {
        let schema = Schema([TransactionModel.self, CategoryModel.self, CreditCardModel.self,
                             GoalModel.self, TravelModel.self, HealthScoreSnapshot.self,
                             RecurrenceRule.self, MerchantCategoryMapping.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let context = container.mainContext
        context.autosaveEnabled = false
        SampleData.populateModelContext(context)
        try context.delete(model: TransactionModel.self)
        let category = try #require(context.fetch(FetchDescriptor<CategoryModel>()).first { $0.transactionType == .expense })
        for index in 0..<3 {
            context.insert(TransactionModel(
                timestamp: Date(timeIntervalSince1970: 1_791_547_200 + Double(index)),
                amount: -Decimal(index + 1) * 10, note: "original \(index)",
                category: category.name, categoryModel: category, currencyCode: "EUR",
                goalId: UUID(), travelId: UUID(), recurrenceRuleId: UUID()
            ))
        }
        try context.save()
        return container
    }

    private func replacement(_ row: TransactionSnapshot, note: String) -> TransactionUpdate {
        TransactionUpdate(id: row.id, input: TransactionInput(
            timestamp: row.timestamp, amount: row.amount, note: note,
            category: row.category, currencyCode: row.currencyCode,
            goalId: row.goalId, travelId: row.travelId,
            categoryPersistentId: row.categoryId, recurrenceRuleId: row.recurrenceRuleId
        ))
    }

    @Test func batchPublishesOnceAndKeepsAnotherWarmedReaderCurrent() async throws {
        let container = try fixture()
        let writer = TransactionActor(modelContainer: container)
        let reader = TransactionActor(modelContainer: container)
        let original = try await writer.fetchAll()
        #expect(try await reader.fetchAll() == original)
        let generation = await writer.snapshotMaterializationGeneration

        await writer.updateBatch(original.prefix(2).map { replacement($0, note: "edited") })

        let actual = try await writer.fetchAll()
        #expect(await writer.snapshotMaterializationGeneration == generation + 1)
        #expect(try await reader.fetchAll() == actual)
        #expect(actual.filter { $0.note == "edited" }.count == 2)
        #expect(actual.last == original.last)
        for (before, after) in zip(original, actual) {
            #expect(before.id == after.id)
            #expect(before.amount == after.amount)
            #expect(before.categoryId == after.categoryId)
            #expect(before.goalId == after.goalId)
            #expect(before.travelId == after.travelId)
            #expect(before.recurrenceRuleId == after.recurrenceRuleId)
        }
    }

    @Test func failedBatchRetriesRowsAndDoesNotPersistTheRejectedRow() async throws {
        let container = try fixture()
        let repo = TransactionActor(modelContainer: container)
        let original = try await repo.fetchAll()
        let generation = await repo.snapshotMaterializationGeneration
        let updates = original.enumerated().map {
            replacement($0.element, note: $0.offset == 1 ? "reject" : "edited")
        }

        // Fail the combined save, then the middle row on retry. This drives real context
        // mutation/rollback/save and verifies that retry proceeds beyond the failed row.
        await repo.updateBatch(updates, saving: { context in
            if try context.fetch(FetchDescriptor<TransactionModel>()).contains(where: { $0.note == "reject" }) {
                throw SaveFailure.injected
            }
            try context.save()
        })

        let actual = try await repo.fetchAll()
        #expect(actual.map(\.note) == ["edited", original[1].note, "edited"])
        #expect(await repo.snapshotMaterializationGeneration == generation + 1)
        let fresh = TransactionActor(modelContainer: container)
        #expect(try await fresh.fetchAll() == actual)
        #expect(actual[1] == original[1])
        // Undo of the same captured selection still restores the successful rows.
        await repo.updateBatch(original.map { replacement($0, note: $0.note) })
        #expect(try await repo.fetchAll() == original)
    }

    @Test func allFailedRowsAreRolledBackBeforeTheNextOperation() async throws {
        let container = try fixture()
        let repo = TransactionActor(modelContainer: container)
        let original = try await repo.fetchAll()
        let generation = await repo.snapshotMaterializationGeneration
        await repo.updateBatch(original.map { replacement($0, note: "rejected") }, saving: { _ in
            throw SaveFailure.injected
        })
        #expect(try await repo.fetchAll() == original)
        #expect(await repo.snapshotMaterializationGeneration == generation)

        await repo.updateBatch([replacement(original[0], note: "next operation")])
        let fresh = TransactionActor(modelContainer: container)
        let actual = try await fresh.fetchAll()
        #expect(actual[0].note == "next operation")
        #expect(Array(actual.dropFirst()) == Array(original.dropFirst()))
    }

    @Test func emptyAndDeletedTargetsDoNotSaveOrRebuildHistory() async throws {
        let container = try fixture()
        let repo = TransactionActor(modelContainer: container)
        let original = try await repo.fetchAll()
        try container.mainContext.delete(model: TransactionModel.self)
        try container.mainContext.save()
        // Bulk SQL deletion bypasses per-model save notifications; direct writers must
        // invalidate explicitly, just like restore/foreground callers.
        await repo.invalidateTransactionSnapshotCache()
        _ = try await repo.fetchAll()
        let generation = await repo.snapshotMaterializationGeneration
        await repo.updateBatch([], saving: { _ in Issue.record("Empty batch must not save") })
        await repo.updateBatch(original.map { replacement($0, note: "deleted") }, saving: { _ in
            Issue.record("Deleted targets must not save")
        })
        #expect(try await repo.fetchAll().isEmpty)
        #expect(await repo.snapshotMaterializationGeneration == generation)
    }

    @Test(arguments: ["note", "amount", "category"])
    func publicBulkEditAndUndoPreserveMetadata(action: String) async throws {
        let container = try fixture()
        let repo = TransactionActor(modelContainer: container)
        let vm = TransactionListViewModel(repo: repo)
        vm.load()
        await vm.loadTask?.value
        let original = try await repo.fetchAll()
        let selected = Set(original.prefix(2).map(\.id))
        let newCategory = try #require(try await repo.fetchCategories().first { $0.transactionType == .income })
        vm.isSelecting = true
        vm.selectedIDs = selected
        var callbacks = 0
        vm.onDataChanged = { callbacks += 1 }
        let generation = await repo.snapshotMaterializationGeneration

        switch action {
        case "amount": vm.bulkSetAmount(25)
        case "category": vm.bulkSetCategory(newCategory)
        default: vm.bulkSetNote("edited")
        }
        await vm.bulkEditTask?.value
        await vm.loadTask?.value
        let actual = try await repo.fetchAll()
        #expect(await repo.snapshotMaterializationGeneration == generation + 1)
        #expect(!vm.isSelecting)
        #expect(vm.selectedIDs.isEmpty)
        #expect(vm.showUndoBanner)
        #expect(callbacks == 1)
        for (before, after) in zip(original, actual) {
            if !selected.contains(before.id) { #expect(after == before); continue }
            #expect(after.timestamp == before.timestamp)
            #expect(after.currencyCode == before.currencyCode)
            #expect(after.travelId == before.travelId)
            #expect(after.recurrenceRuleId == before.recurrenceRuleId)
            if action == "category" {
                #expect(after.categoryId == newCategory.persistentId)
                #expect(after.goalId == nil)
                #expect(after.amount == abs(before.amount))
            } else {
                #expect(after.goalId == before.goalId)
                #expect(after.categoryId == before.categoryId)
                #expect(after.amount == (action == "amount" ? -25 : before.amount))
                #expect(after.note == (action == "note" ? "edited" : before.note))
            }
        }
        vm.undoPending()
        await vm.bulkEditTask?.value
        await vm.loadTask?.value
        #expect(try await repo.fetchAll() == original)
        #expect(vm.transactions == original)
        #expect(await repo.snapshotMaterializationGeneration == generation + 2)
        #expect(callbacks == 2)
        #expect(!vm.showUndoBanner)
    }

    @Test func publicBulkEditFinalizesAPendingDeleteBeforeReloadAndUndo() async throws {
        let container = try fixture()
        let repo = TransactionActor(modelContainer: container)
        let vm = TransactionListViewModel(repo: repo)
        vm.load()
        await vm.loadTask?.value
        let original = try await repo.fetchAll()
        // Non-recurring deletion avoids the separate recurrence scope prompt.
        let context = container.mainContext
        let deletedID = original[0].id
        let deletedModel = try #require(context.model(for: deletedID) as? TransactionModel)
        deletedModel.recurrenceRuleId = nil
        try context.save()
        await repo.invalidateTransactionSnapshotCache()
        vm.reload()
        await vm.loadTask?.value
        let deleted = try #require(vm.transactions.first { $0.id == deletedID })
        vm.delete(deleted)
        let deleteTimer = vm.pendingDeletionTask
        vm.selectedIDs = [original[1].id]
        vm.bulkSetNote("edited after delete")
        await vm.bulkEditTask?.value
        await vm.loadTask?.value
        await deleteTimer?.value
        let after = try await repo.fetchAll()
        #expect(!after.contains { $0.id == deletedID })
        #expect(after.first { $0.id == original[1].id }?.note == "edited after delete")
        #expect(vm.pendingDeletion.isEmpty)
        #expect(vm.showUndoBanner)
        vm.undoPending()
        await vm.bulkEditTask?.value
        await vm.loadTask?.value
        #expect(try await repo.fetchAll() == Array(original.dropFirst()))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PFT_BULK_WIDGET_CHECK"] == "1"
                   && Bundle.main.bundleIdentifier == "rizzoG99.PersonalFinanceTraker.test"))
    func monetaryEditAndUndoWriteTheFinalWidgetValues() async throws {
        let group = try #require(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier))
        let url = group.appending(path: "safe_to_spend_snapshot.json")
        let prior = try? Data(contentsOf: url)
        let defaults = UserDefaults.standard
        let priorDay = defaults.object(forKey: "payCycleStartDay")
        defaults.set(1, forKey: "payCycleStartDay")
        defer {
            if let prior { try? prior.write(to: url, options: .atomic) }
            else { try? FileManager.default.removeItem(at: url) }
            if let priorDay { defaults.set(priorDay, forKey: "payCycleStartDay") }
            else { defaults.removeObject(forKey: "payCycleStartDay") }
        }
        let container = try fixture()
        // Keep these rows in the current cycle so changed amounts affect the widget.
        for row in try container.mainContext.fetch(FetchDescriptor<TransactionModel>()) {
            row.timestamp = .now
        }
        try container.mainContext.save()
        let repo = TransactionActor(modelContainer: container)
        let vm = TransactionListViewModel(repo: repo)
        vm.load()
        await vm.loadTask?.value
        await repo.refreshSafeToSpendWidgetSnapshot()
        let original = try await repo.fetchAll()
        let before = try #require(SafeToSpendSnapshot.load())
        vm.selectedIDs = Set(original.prefix(2).map(\.id))
        vm.bulkSetAmount(100)
        await vm.bulkEditTask?.value
        await vm.loadTask?.value
        let widget = try #require(SafeToSpendSnapshot.load())
        let expected = SafeToSpendSnapshotBuilder.build(
            transactions: try await repo.fetchAll(), activeRules: try await repo.fetchActiveRecurrenceRules(),
            payCycleStartDay: AppSettings.storedStartDay, bufferPercent: AppSettings.storedBufferPercent,
            currencyService: CurrencyService(), now: widget.generatedAt
        )
        #expect(widget == expected)
        #expect(widget.amount != before.amount)
        vm.undoPending()
        await vm.bulkEditTask?.value
        await vm.loadTask?.value
        let restored = try #require(SafeToSpendSnapshot.load())
        #expect(restored.amount == before.amount)
        #expect(restored.currencyCode == before.currencyCode)
        #expect(restored.payday == before.payday)
        #expect(restored.hasIncome == before.hasIncome)
    }
}
