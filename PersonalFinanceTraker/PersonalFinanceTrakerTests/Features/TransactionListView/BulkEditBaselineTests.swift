import Foundation
import SwiftData
import Testing
@testable import PersonalFinanceTraker

extension PerformanceRecorderSerialTests {
/// Opt-in, disk-backed PERF-201 baseline. Run alone in the isolated TEST scheme:
/// TEST_RUNNER_PFT_BULK_BASELINE=1 PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST scripts/xcb test
/// -only-testing:PersonalFinanceTrakerTests/BulkEditBaselineTests
/// Measures the real ViewModel/repository/widget path, excluding AppShell fan-out and UI frames.
@Suite(.serialized)
struct BulkEditBaselineTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PFT_BULK_BASELINE"] == "1"
                   && Bundle.main.bundleIdentifier == "rizzoG99.PersonalFinanceTraker.test"))
    @MainActor func editAndUndoOnFiveThousandTransactions() async throws {
        let wasEnabled = PerformanceAuditRecorder.isEnabled
        PerformanceAuditRecorder.resetForTesting(isEnabled: true)
        defer { PerformanceAuditRecorder.resetForTesting(isEnabled: wasEnabled) }

        // Only the TEST widget receives the real repository side effects. Restore its prior file.
        let group = try #require(FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ))
        let widgetURL = group.appending(path: "safe_to_spend_snapshot.json")
        let priorWidget = try? Data(contentsOf: widgetURL)
        let defaults = UserDefaults.standard
        let priorDay = defaults.object(forKey: "payCycleStartDay")
        let priorBuffer = defaults.object(forKey: "safeToSpendBufferPercent")
        defaults.set(1, forKey: "payCycleStartDay")
        defaults.set(5, forKey: "safeToSpendBufferPercent")
        defer {
            if let priorWidget { try? priorWidget.write(to: widgetURL, options: .atomic) }
            else { try? FileManager.default.removeItem(at: widgetURL) }
            if let priorDay { defaults.set(priorDay, forKey: "payCycleStartDay") }
            else { defaults.removeObject(forKey: "payCycleStartDay") }
            if let priorBuffer { defaults.set(priorBuffer, forKey: "safeToSpendBufferPercent") }
            else { defaults.removeObject(forKey: "safeToSpendBufferPercent") }
        }

        let clock = ContinuousClock()
        let phaseNames = ["TransactionActor.store.fetch", "TransactionActor.snapshots.map",
                          "SafeToSpend.refresh", "SafeToSpend.snapshot.write"]
        for (round, order) in [[1, 10, 100], [100, 1, 10], [10, 100, 1]].enumerated() {
            let directory = FileManager.default.temporaryDirectory.appending(path: "PERF201-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let container = try makeFixture(at: directory.appending(path: "ledger.store"))
            let repo = TransactionActor(modelContainer: container)
            let vm = TransactionListViewModel(repo: repo)
            var notifications = 0
            vm.onDataChanged = { notifications += 1 }
            vm.load()
            await vm.loadTask?.value
            await repo.refreshSafeToSpendWidgetSnapshot()
            let original = try await repo.fetchAll()
            let initialWidget = try #require(SafeToSpendSnapshot.load())
            #expect(original.count == 5_000)
            let saves = BulkBaselineSaveCounter(container: container)

            for count in order {
                let selected = Set(original.prefix(count).map(\.id))
                vm.isSelecting = true
                vm.selectedIDs = selected
                await vm.groupingTask?.value

                for action in ["edit", "undo"] {
                    let before = PerformanceAuditRecorder.testingSnapshot()
                    let beforeGeneration = await repo.snapshotMaterializationGeneration
                    let beforeSaves = saves.count
                    let beforeNotifications = notifications
                    let interval = PerformanceAuditRecorder.begin(
                        "PERF201.bulk.operation", metadata: "round=\(round) action=\(action) selected=\(count) ledger=5000"
                    )
                    let start = clock.now
                    if action == "edit" { vm.bulkSetNote("PERF201 changed") }
                    else { vm.undoPending() }
                    await vm.bulkEditTask?.value
                    let mutationReturned = start.duration(to: clock.now)
                    await vm.loadTask?.value
                    await vm.groupingTask?.value
                    let localSettled = start.duration(to: clock.now)
                    PerformanceAuditRecorder.end(interval)
                    let generation = await repo.snapshotMaterializationGeneration - beforeGeneration
                    let after = PerformanceAuditRecorder.testingSnapshot()

                    // Correctness oracles reach the real public caller and persistent repository.
                    let actual = try await repo.fetchAll()
                    #expect(actual.count == 5_000)
                    #expect(Set(actual.map(\.id)) == Set(original.map(\.id)))
                    #expect(Set(actual.filter { !selected.contains($0.id) })
                            == Set(original.filter { !selected.contains($0.id) }))
                    if action == "edit" {
                        #expect(Set(actual.filter { $0.note == "PERF201 changed" }.map(\.id)) == selected)
                        #expect(vm.showUndoBanner)
                    } else {
                        #expect(Set(actual) == Set(original))
                        #expect(!vm.showUndoBanner)
                    }
                    #expect(vm.transactions == actual)
                    #expect(vm.groupedItems.flatMap(\.1).compactMap(\.transaction).count == 5_000)
                    #expect(notifications - beforeNotifications == 1)
                    let widget = try #require(SafeToSpendSnapshot.load())
                    #expect(widget.amount == initialWidget.amount)
                    #expect(widget.currencyCode == initialWidget.currencyCode)
                    #expect(widget.payday == initialWidget.payday)
                    #expect(widget.hasIncome == initialWidget.hasIncome)

                    var record: [String: Any] = [
                        "round": round, "action": action, "selected_rows": count, "ledger_rows": 5_000,
                        "mutation_return_ms": milliseconds(mutationReturned),
                        "local_vm_settled_ms": milliseconds(localSettled),
                        "saves": saves.count - beforeSaves, "materializations": generation,
                        "data_change_callbacks": notifications - beforeNotifications,
                        "locale": Locale.current.identifier, "time_zone": TimeZone.current.identifier,
                        "pay_cycle_day": AppSettings.storedStartDay, "buffer_percent": AppSettings.storedBufferPercent,
                    ]
                    for name in phaseNames {
                        let starts = (after.counters["\(name).start"] ?? 0) - (before.counters["\(name).start"] ?? 0)
                        let elapsed = (after.totalDurationNanoseconds[name] ?? 0) - (before.totalDurationNanoseconds[name] ?? 0)
                        record["\(name).starts"] = starts
                        record["\(name).elapsed_ms"] = Double(elapsed) / 1_000_000
                        #expect((after.activeIntervals[name] ?? 0) == 0)
                        #expect((after.counters["\(name).failed"] ?? 0) == (before.counters["\(name).failed"] ?? 0))
                    }
                    // Reject process-wide recorder contamination; generation and saves are fixture-owned.
                    #expect(record["TransactionActor.snapshots.map.starts"] as? Int == Int(generation))
                    #expect(record["TransactionActor.store.fetch.starts"] as? Int == Int(generation))
                    record["WidgetKit.reload.request"] = (after.counters["WidgetKit.reload.request"] ?? 0)
                        - (before.counters["WidgetKit.reload.request"] ?? 0)
                    // Opt-in follow-up budget; leaves the original pre-fix baseline reproducible
                    // without assuming a particular implementation or a simulator timing limit.
                    if ProcessInfo.processInfo.environment["PFT_BULK_REQUIRE_BATCH"] == "1" {
                        #expect(generation == 1)
                        for key in ["saves", "SafeToSpend.refresh.starts", "SafeToSpend.snapshot.write.starts",
                                    "WidgetKit.reload.request"] {
                            #expect(record[key] as? Int == 1)
                        }
                    }
                    let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                    print("PFT_BULK_BASELINE \(String(decoding: json, as: UTF8.self))")
                }
            }
        }
    }

    /// Explicit red-capable structural budget, separate from ordinary correctness tests.
    /// Before batching, one selected row passes and two selected rows fail this same oracle.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PFT_BULK_SINGLE_FLUSH_CHECK"] == "1"
                   && Bundle.main.bundleIdentifier == "rizzoG99.PersonalFinanceTraker.test"),
          arguments: [1, 2])
    @MainActor func oneBulkOperationMaterializesHistoryOnce(selectedCount: Int) async throws {
        let group = try #require(FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ))
        let widgetURL = group.appending(path: "safe_to_spend_snapshot.json")
        let priorWidget = try? Data(contentsOf: widgetURL)
        defer {
            if let priorWidget { try? priorWidget.write(to: widgetURL, options: .atomic) }
            else { try? FileManager.default.removeItem(at: widgetURL) }
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "PERF201-minimal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeFixture(at: directory.appending(path: "ledger.store"), count: selectedCount)
        let repo = TransactionActor(modelContainer: container)
        let vm = TransactionListViewModel(repo: repo)
        vm.load()
        await vm.loadTask?.value
        vm.selectedIDs = Set(vm.transactions.map(\.id))
        let before = await repo.snapshotMaterializationGeneration
        vm.bulkSetNote("PERF201 changed")
        await vm.bulkEditTask?.value
        await vm.loadTask?.value
        await vm.groupingTask?.value
        await vm.commitPending()
        let materializations = await repo.snapshotMaterializationGeneration - before
        #expect(vm.transactions.count == selectedCount)
        #expect(vm.transactions.allSatisfy { $0.note == "PERF201 changed" })
        print("PFT_BULK_SINGLE_FLUSH selected=\(selectedCount) materializations=\(materializations) budget=1")
        #expect(materializations == 1, "One logical bulk edit should rebuild history once, regardless of selected row count")
    }

    @MainActor private func makeFixture(at url: URL, count: Int = 5_000) throws -> ModelContainer {
        let schema = Schema([TransactionModel.self, CategoryModel.self, CreditCardModel.self,
                             GoalModel.self, TravelModel.self, HealthScoreSnapshot.self,
                             RecurrenceRule.self, MerchantCategoryMapping.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ])
        let context = container.mainContext
        context.autosaveEnabled = false
        SampleData.populateModelContext(context)
        try context.delete(model: TransactionModel.self)
        let categories = try context.fetch(FetchDescriptor<CategoryModel>(sortBy: [SortDescriptor(\.name)]))
        let expenses = categories.filter { $0.transactionType == .expense }
        let income = categories.filter { $0.transactionType == .income }
        let anchor = Date(timeIntervalSince1970: 1_791_547_200)
        for index in 0..<count {
            let isIncome = index.isMultiple(of: 20)
            let pool = isIncome ? income : expenses
            let category = pool[index % pool.count]
            let cents = isIncome ? 180_000 + ((index * 7_919) % 220_000) : 250 + ((index * 7_919) % 24_750)
            context.insert(TransactionModel(
                timestamp: anchor.addingTimeInterval(-Double(index % 1_825) * 86_400 + Double((index * 7_919) % 86_400)),
                amount: Decimal(isIncome ? cents : -cents) / 100,
                note: "PERF201 fixture \(index)", category: category.name, categoryModel: category, currencyCode: "EUR"
            ))
        }
        try context.save()
        return container
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }
}
}

/// Save notifications are observed synchronously and counted only for this fixture's container.
private final class BulkBaselineSaveCounter: @unchecked Sendable {
    private let container: ModelContainer
    private let lock = NSLock()
    private var value = 0
    private var observer: NSObjectProtocol?

    init(container: ModelContainer) {
        self.container = container
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) {
            [weak self] notification in
            guard let self, let context = notification.object as? ModelContext,
                  context.container === self.container else { return }
            self.lock.lock()
            self.value += 1
            self.lock.unlock()
        }
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
