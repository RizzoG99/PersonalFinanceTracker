import Foundation
import SwiftData
import Testing
@testable import PersonalFinanceTraker

@Suite(.serialized)
@MainActor
struct TransactionActorCacheTests {
    private func makeSeededActor() throws -> TransactionActor {
        let schema = Schema([TransactionModel.self, CategoryModel.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        context.insert(
            TransactionModel(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                amount: -12,
                note: "Seed transaction",
                category: "Food"
            )
        )
        try context.save()
        return TransactionActor(modelContainer: container)
    }

    @Test func fetchAllReusesSnapshotsAfterTheFirstStoreRead() async throws {
        let actor = try makeSeededActor()

        let first = try await actor.fetchAll()
        let second = try await actor.fetchAll()

        #expect(first == second)
        #expect(await actor.snapshotMaterializationGeneration == 1)
    }

    @Test func transactionMutationInvalidatesTheSnapshotCache() async throws {
        let actor = try makeSeededActor()

        _ = try await actor.fetchAll()
        try await actor.add(
            TransactionInput(
                timestamp: Date(timeIntervalSince1970: 1_700_000_100),
                amount: -8,
                note: "Added after cache",
                category: "Food",
                currencyCode: "EUR"
            )
        )
        let snapshots = try await actor.fetchAll()

        #expect(snapshots.map(\.note).contains("Added after cache"))
        // One store read warms the cache, the mutation clears it, then the widget refresh
        // repopulates it. The final user-facing read must therefore be a cache hit.
        #expect(await actor.snapshotMaterializationGeneration == 2)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            TransactionModel.self, CategoryModel.self, TravelModel.self,
            RecurrenceRule.self, GoalModel.self, HealthScoreSnapshot.self
        ])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
    }

    @Test func anotherActorSaveInvalidatesAWarmedReader() async throws {
        let container = try makeContainer()
        let reader = TransactionActor(modelContainer: container)
        let writer = TransactionActor(modelContainer: container)
        #expect(try await reader.fetchAll().isEmpty)

        try await writer.add(TransactionInput(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000), amount: -8,
            note: "Intent write", category: "Food", currencyCode: "EUR"
        ))

        #expect(try await reader.fetchAll().map(\.note) == ["Intent write"])
    }

    @Test func directContextSaveRefreshesAlreadyMaterializedValues() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let category = CategoryModel(name: "Food", systemImage: "fork.knife", type: .expense)
        let transaction = TransactionModel(timestamp: .now, amount: -12, note: "Before", category: "Food")
        transaction.categoryModel = category
        context.insert(category)
        context.insert(transaction)
        try context.save()
        let reader = TransactionActor(modelContainer: container)
        let first = try await reader.fetchAll()
        #expect(first.first?.note == "Before")

        transaction.note = "After"
        category.systemImage = "cart.fill"
        category.colorToken = "categoryRed"
        try context.save()

        let updated = try await reader.fetchAll()
        #expect(updated.first?.note == "After")
        #expect(updated.first?.categorySystemImage == "cart.fill")
        #expect(updated.first?.categoryColorToken == "categoryRed")

        context.delete(category)
        try context.save()
        let uncategorized = try await reader.fetchAll()
        #expect(uncategorized.first?.note == "After")
        #expect(uncategorized.first?.categoryId == nil)
        #expect(uncategorized.first?.categorySystemImage == nil)
        #expect(uncategorized.first?.categoryColorToken == nil)

        context.delete(transaction)
        try context.save()
        #expect(try await reader.fetchAll().isEmpty)
    }

    @Test func explicitInvalidationRefreshesAnAlreadyRegisteredModel() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let transaction = TransactionModel(timestamp: .now, amount: -12, note: "Before", category: "Food")
        context.insert(transaction)
        try context.save()
        let reader = TransactionActor(modelContainer: container)
        _ = try await reader.fetchAll()
        transaction.note = "Restored"
        try context.save()
        await reader.invalidateTransactionSnapshotCache()

        #expect(try await reader.fetchAll().first?.note == "Restored")
    }

    @Test func unrelatedSavesDoNotRematerializeTransactions() async throws {
        let container = try makeContainer()
        let reader = TransactionActor(modelContainer: container)
        _ = try await reader.fetchAll()
        container.mainContext.insert(HealthScoreSnapshot(
            timestamp: .now, score: 50, savingsScore: 50, stabilityScore: 50,
            adherenceScore: 50, subscriptionScore: 50
        ))
        try container.mainContext.save()
        _ = try await reader.fetchAll()
        #expect(await reader.snapshotMaterializationGeneration == 1)

        let otherContainer = try makeContainer()
        otherContainer.mainContext.insert(TransactionModel(timestamp: .now, amount: -8, note: "Other store", category: "Food"))
        try otherContainer.mainContext.save()
        #expect(try await reader.fetchAll().isEmpty)
        #expect(await reader.snapshotMaterializationGeneration == 1)
    }

    @Test func batchUpdateTravelAndDeletionKeepBothActorsCurrent() async throws {
        let container = try makeContainer()
        let reader = TransactionActor(modelContainer: container)
        let writer = TransactionActor(modelContainer: container)
        _ = try await reader.fetchAll()
        let input = TransactionInput(timestamp: .now, amount: -12, note: "Batch", category: "Food", currencyCode: "EUR")
        try await writer.addBatch([input, input])
        let batch = try await reader.fetchAll()
        #expect(batch.count == 2)
        let first = try #require(batch.first)
        try await writer.update(id: first.id, with: TransactionInput(
            timestamp: .now, amount: -20, note: "Edited", category: "Food", currencyCode: "EUR"
        ))
        #expect(try await reader.fetchAll().first(where: { $0.id == first.id })?.amount == -20)
        let travel = try await writer.addTravel(name: "Trip", symbolName: "airplane")
        try await writer.setTravel(travel, forIDs: [first.id])
        #expect(try await reader.fetchAll().first(where: { $0.id == first.id })?.travelId == travel)
        try await writer.deleteTravel(id: travel)
        #expect(try await reader.fetchAll().allSatisfy { $0.travelId == nil })
        try await writer.delete(id: first.id)
        #expect(try await reader.fetchAll().count == 1)
        try await writer.deleteAllTransactions()
        #expect(try await reader.fetchAll().isEmpty)
    }

    @Test func recurrenceMaterializationAndDeletionInvalidateOtherReaders() async throws {
        let container = try makeContainer()
        let reader = TransactionActor(modelContainer: container)
        let writer = TransactionActor(modelContainer: container)
        _ = try await reader.fetchAll()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let rule = RecurrenceRuleInput(
            frequency: .monthly, interval: 1, startDate: date, amount: -12,
            note: "Recurring", category: "Food", currencyCode: "EUR"
        )
        try await writer.addRecurrenceRule(rule)
        try await writer.materializeOccurrences(ruleId: rule.id, inputs: [TransactionInput(
            timestamp: date, amount: -12, note: "Occurrence", category: "Food", currencyCode: "EUR"
        )], newCursor: date)
        #expect(try await reader.fetchAll().first?.recurrenceRuleId == rule.id)
        try await writer.deleteOccurrences(recurrenceRuleId: rule.id, from: date)
        #expect(try await reader.fetchAll().isEmpty)
    }

    @Test func shellAndBackupShareOneForegroundInvalidation() async throws {
        let container = try makeContainer()
        let models = AppShellModels(modelContainer: container)
        _ = try await models.repo.fetchAll()
        let revisions = TransactionSnapshotRevision.shared
        let before = revisions.revision(for: container)
        await models.prepareForForegroundReads()
        #expect(revisions.revision(for: container) == before)

        models.recordBackgroundForSnapshotRefresh()
        async let shell: Void = models.prepareForForegroundReads()
        async let backup: Void = models.prepareForForegroundReads()
        _ = await (shell, backup)
        #expect(revisions.revision(for: container) == before + 1)
        _ = try await models.repo.fetchAll()
        await models.prepareForForegroundReads()
        _ = try await models.repo.fetchAll()
        #expect(await models.repo.snapshotMaterializationGeneration == 2)
    }

    @Test func foregroundInvalidationSeesAWritingContainerOutsideTheProcessRevision() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pft-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([TransactionModel.self, CategoryModel.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appending(path: "ledger.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let externalContainer = try ModelContainer(for: schema, configurations: [configuration])
        let models = AppShellModels(modelContainer: container)
        #expect(try await models.repo.fetchAll().isEmpty)
        externalContainer.mainContext.insert(TransactionModel(timestamp: .now, amount: -12, note: "External", category: "Food"))
        try externalContainer.mainContext.save()

        // A second container deliberately cannot advance this container's local revision;
        // this represents a save for which no in-process notification is available.
        #expect(try await models.repo.fetchAll().isEmpty)
        models.recordBackgroundForSnapshotRefresh()
        await models.prepareForForegroundReads()
        #expect(try await models.repo.fetchAll().map(\.note) == ["External"])
    }
}
