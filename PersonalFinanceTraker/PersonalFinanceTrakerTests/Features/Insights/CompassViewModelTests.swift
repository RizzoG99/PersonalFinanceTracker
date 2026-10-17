import Testing
import Foundation
import SwiftData
@testable import PersonalFinanceTraker

/// Explicit repository suspension; no scheduler delays or sleep-based verdicts.
@MainActor
private final class InsightsReadGate<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?

    func read() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            precondition(self.continuation == nil)
            self.continuation = continuation
            entered = true
            enteredWaiter?.resume()
            enteredWaiter = nil
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release(_ result: Result<Value, Error>) {
        precondition(continuation != nil)
        continuation?.resume(with: result)
        continuation = nil
    }
}

extension PerformanceRecorderSerialTests {
@MainActor
@Suite(.serialized)
struct CompassViewModelTests {

    @Test(arguments: [1, 5_000]) func revisionsAndNavigationCoalesceWithoutPublishingSupersededRows(count: Int) async throws {
        let wasEnabled = PerformanceAuditRecorder.isEnabled
        PerformanceAuditRecorder.resetForTesting(isEnabled: true)
        defer { PerformanceAuditRecorder.resetForTesting(isEnabled: wasEnabled) }
        let repo = MockTransactionRepository()
        let anchor = Date(timeIntervalSince1970: 1_791_547_200)
        let old = (0..<count).map { _ in TransactionSnapshot.test(timestamp: anchor, amount: -12, category: "Food") }
        let latest = (0..<count).map { _ in TransactionSnapshot.test(timestamp: anchor, amount: -37, category: "Food") }
        let vm = CompassViewModel(repo: repo)
        let firstRead = InsightsReadGate<[TransactionSnapshot]>()
        let followUpRead = InsightsReadGate<[TransactionSnapshot]>()
        repo.fetchAllHandler = {
            if repo.fetchAllCallCount == 1 { return try await firstRead.read() }
            return try await followUpRead.read()
        }
        vm.load()
        let owner = vm.loadTask
        await firstRead.waitUntilEntered()
        // Same model receives a revision plus repeated appearance/dismiss requests.
        vm.load()
        vm.load()
        vm.load()
        vm.explorerPeriod = .current(.year, now: anchor)
        vm.explorerType = .income
        vm.explorerType = .expenses
        let selected = vm.explorerPeriod
        firstRead.release(.success(old))
        await followUpRead.waitUntilEntered()
        #expect(vm.transactions.isEmpty)
        #expect(vm.publishedGeneration == 0)
        #expect(repo.fetchAllCallCount == 2)
        followUpRead.release(.success(latest))
        await owner?.value
        let counters = PerformanceAuditRecorder.testingSnapshot()
        print("PERF111 followup inputs=\(count) requests=\(vm.requestedGeneration) published=\(vm.publishedGeneration) reads=\(repo.fetchAllCallCount) starts=\(counters.counters["Insights.load.start", default: 0]) commits=\(counters.counters["Insights.load.commit", default: 0]) max_active=\(counters.maximumConcurrentIntervals["Insights.load", default: 0])")
        #expect(vm.transactions.map(\.id) == latest.map(\.id))
        #expect(vm.explorer.total == Decimal(37 * count))
        #expect(vm.explorer.bars.reduce(Decimal.zero) { $0 + $1.amount } == vm.explorer.total)
        #expect(vm.explorerPeriod == selected)
        #expect(vm.publishedGeneration == vm.requestedGeneration)
        #expect(counters.maximumConcurrentIntervals["Insights.load"] == 1)
        #expect(counters.counters["Insights.load.commit"] == 1)
        #expect(repo.saveSnapshotCalledCount == 1)
    }

    @Test func revisionDuringTheFollowUpIsNotLostEvenWhenTheFirstReadFails() async {
        let repo = MockTransactionRepository()
        let vm = CompassViewModel(repo: repo)
        let first = InsightsReadGate<[TransactionSnapshot]>()
        let second = InsightsReadGate<[TransactionSnapshot]>()
        let latest = [makeExpense(amount: 51)]
        repo.fetchAllHandler = {
            switch repo.fetchAllCallCount {
            case 1: return try await first.read()
            case 2: return try await second.read()
            default: return latest
            }
        }
        vm.load()
        let owner = vm.loadTask
        await first.waitUntilEntered()
        vm.load()
        first.release(.failure(MockTransactionRepository.MockError.forced))
        await second.waitUntilEntered()
        vm.load()
        second.release(.success([makeExpense(amount: 20)]))
        await owner?.value
        #expect(repo.fetchAllCallCount == 3)
        #expect(vm.transactions.map(\.id) == latest.map(\.id))
        #expect(vm.publishedGeneration == 3)
        #expect(vm.loadTask == nil)
    }

    @Test func retryAfterFailureAndCancellationOfAnAwaitingCaller() async {
        let repo = MockTransactionRepository()
        let vm = CompassViewModel(repo: repo)
        repo.shouldThrow = true
        await vm.reloadData()
        #expect(vm.loadTask == nil)
        #expect(vm.publishedGeneration == 0)
        repo.shouldThrow = false
        let read = InsightsReadGate<[TransactionSnapshot]>()
        repo.fetchAllHandler = { try await read.read() }
        let waiter = Task { await vm.reloadData() }
        await read.waitUntilEntered()
        waiter.cancel()
        read.release(.success([makeExpense(amount: 23)]))
        await waiter.value
        #expect(vm.transactions.first?.amount == -23)
        #expect(vm.publishedGeneration == vm.requestedGeneration)
        repo.fetchAllHandler = nil
        repo.shouldThrow = true
        await vm.reloadData()
        #expect(vm.transactions.first?.amount == -23)
        #expect(vm.loadTask == nil)
        repo.shouldThrow = false
        repo.stubbedTransactions = [makeExpense(amount: 41)]
        await vm.reloadData()
        #expect(vm.transactions.first?.amount == -41)
    }

    @Test func payCycleAndScorePreferenceChangesDuringCategoryReadUseLatestInputs() async throws {
        let defaults = UserDefaults.standard
        let savedDay = defaults.object(forKey: "payCycleStartDay")
        let savedIgnore = defaults.object(forKey: "healthScore.ignoreSubscriptions")
        defer {
            defaults.set(savedDay, forKey: "payCycleStartDay")
            defaults.set(savedIgnore, forKey: "healthScore.ignoreSubscriptions")
        }
        defaults.set(1, forKey: "payCycleStartDay")
        defaults.set(false, forKey: "healthScore.ignoreSubscriptions")
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [makeIncome(amount: 2000), makeExpense(amount: 300), makeExpense(amount: 200, monthsAgo: 1)]
        let vm = CompassViewModel(repo: repo)
        let categories = InsightsReadGate<[CategorySnapshot]>()
        repo.fetchCategoriesHandler = {
            if repo.fetchCategoriesCallCount == 1 { return try await categories.read() }
            return []
        }
        vm.load()
        let owner = vm.loadTask
        await categories.waitUntilEntered()
        defaults.set(27, forKey: "payCycleStartDay")
        vm.load() // payCycleAware's actual ViewModel boundary
        vm.ignoreSubscriptions = true
        vm.explorerPeriod = vm.explorerPeriod.previous()
        let selected = vm.explorerPeriod
        #expect(vm.transactions.isEmpty) // no transaction-only partial publication
        categories.release(.success([]))
        await owner?.value
        #expect(vm.publishedGeneration == 3)
        #expect(repo.fetchAllCallCount == 2)
        #expect(vm.explorerPeriod == selected)
        let reference = CompassViewModel(repo: repo)
        reference.explorerPeriod = selected
        await reference.reloadData()
        #expect(vm.healthScore?.score == reference.healthScore?.score)
        #expect(vm.healthScore?.components.map(\.score) == reference.healthScore?.components.map(\.score))
        #expect(vm.monthlyRecap?.spent == reference.monthlyRecap?.spent)
        #expect(vm.monthlyRecap?.income == reference.monthlyRecap?.income)
        #expect(vm.averageExpenses == reference.averageExpenses)
        #expect(vm.averageIncome == reference.averageIncome)
        #expect(vm.averageSavings == reference.averageSavings)
        #expect(vm.explorer.total == reference.explorer.total)
        #expect(vm.explorer.trends.map { $0.category.amount } == reference.explorer.trends.map { $0.category.amount })
    }

    @Test(arguments: [1, 6]) func revisionDuringSnapshotReadSuppressesObsoletePublication(limit: Int) async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [makeExpense(amount: 12)]
        let vm = CompassViewModel(repo: repo)
        let snapshotRead = InsightsReadGate<[HealthScoreSnapshotData]>()
        var didSuspend = false
        repo.fetchSnapshotsHandler = { requestedLimit in
            if requestedLimit == limit && !didSuspend {
                didSuspend = true
                return try await snapshotRead.read()
            }
            return repo.stubbedSnapshots
        }
        vm.load()
        let owner = vm.loadTask
        await snapshotRead.waitUntilEntered()
        repo.stubbedTransactions = [makeExpense(amount: 37)]
        vm.load()
        #expect(vm.transactions.isEmpty)
        snapshotRead.release(.success([]))
        await owner?.value
        #expect(repo.saveSnapshotCalledCount == 1)
        #expect(vm.transactions.first?.amount == -37)
        #expect(vm.scoreSnapshots.first?.score == vm.healthScore?.score)
        #expect(vm.publishedGeneration == 2)
    }

    @Test func foregroundAndInProcessMutationsRefreshTheRealRepository() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "perf111-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([TransactionModel.self, CategoryModel.self, CreditCardModel.self,
                             GoalModel.self, TravelModel.self, HealthScoreSnapshot.self,
                             RecurrenceRule.self, MerchantCategoryMapping.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appending(path: "ledger.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        SampleData.populateModelContext(container.mainContext)
        try container.mainContext.delete(model: TransactionModel.self)
        try container.mainContext.save()
        let external = try ModelContainer(for: schema, configurations: [configuration])
        let models = AppShellModels(modelContainer: container)
        await models.compass.reloadData()
        #expect(models.compass.transactions.isEmpty)
        external.mainContext.insert(TransactionModel(timestamp: .now, amount: -12, note: "External", category: "Food"))
        try external.mainContext.save()
        #expect(try await models.repo.fetchAll().isEmpty)
        models.recordBackgroundForSnapshotRefresh()
        await models.prepareForForegroundReads()
        await models.compass.reloadData()
        #expect(models.compass.transactions.map(\.note) == ["External"])
        try await models.repo.add(TransactionInput(timestamp: .now, amount: -37, note: "Local", category: "Food", currencyCode: "EUR"))
        models.compass.load()
        await models.compass.loadTask?.value
        #expect(models.compass.transactions.count == 2)
        #expect(models.compass.explorer.total == 49)
    }

    @Test func anAlreadyIssuedSnapshotSaveDoesNotAllowAnObsoleteUICommit() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [makeIncome(amount: 2000), makeExpense(amount: 100)]
        let vm = CompassViewModel(repo: repo)
        let save = InsightsReadGate<Void>()
        repo.saveSnapshotHandler = { _ in try await save.read() }
        vm.load()
        let owner = vm.loadTask
        await save.waitUntilEntered()
        repo.stubbedTransactions = [makeExpense(amount: 5000)]
        vm.load()
        #expect(vm.publishedGeneration == 0)
        save.release(.success(()))
        await owner?.value
        #expect(vm.transactions.first?.amount == -5000)
        #expect(vm.publishedGeneration == 2)
        // Existing once-per-day history policy: a save valid when issued is retained.
        #expect(repo.saveSnapshotCalledCount == 1)
        #expect(vm.scoreSnapshots.count == 1)
    }

    @Test func awaitedReloadJoinsAnAppearanceLoadAndWaitsForTheLatestRevision() async {
        let repo = MockTransactionRepository()
        let vm = CompassViewModel(repo: repo)
        let read = InsightsReadGate<[TransactionSnapshot]>()
        repo.fetchAllHandler = { try await read.read() }
        vm.load()
        await read.waitUntilEntered()
        let latest = [makeExpense(amount: 37)]
        repo.fetchAllHandler = nil
        repo.stubbedTransactions = latest
        // The release runs only once reloadData suspends awaiting the shared owner.
        let release = Task { read.release(.success([makeExpense(amount: 12)])) }
        await vm.reloadData()
        await release.value
        #expect(repo.fetchAllCallCount == 2)
        #expect(vm.transactions.map(\.id) == latest.map(\.id))
        #expect(vm.publishedGeneration == 2)
        #expect(vm.loadTask == nil)
    }

    private func makeVM(transactions: [TransactionSnapshot]) async -> CompassViewModel {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = transactions
        let vm = CompassViewModel(repo: repo)
        // Awaits the load directly rather than sleeping past it. `load()` is
        // fire-and-forget, so the previous 100ms sleep was a guess that came up
        // short when the full suite ran and the load was scheduled late.
        await vm.reloadData()
        return vm
    }

    private func makeIncome(amount: Decimal, monthsAgo: Int = 0) -> TransactionSnapshot {
        let date = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: Date()) ?? Date()
        return .test(timestamp: date, amount: amount, category: "Salary")
    }

    private func makeExpense(amount: Decimal, category: String = "Groceries", monthsAgo: Int = 0) -> TransactionSnapshot {
        let date = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: Date()) ?? Date()
        return .test(timestamp: date, amount: -abs(amount), category: category)
    }

    @Test("explorer ‹ stops at the period holding the first transaction")
    func explorerPreviousStopsAtFirstTransaction() async {
        let empty = await makeVM(transactions: [])
        #expect(!empty.canGoToPreviousPeriod)

        let startedToday = await makeVM(transactions: [makeExpense(amount: 10)])
        #expect(!startedToday.canGoToPreviousPeriod)

        let since2MonthsAgo = await makeVM(transactions: [makeExpense(amount: 10, monthsAgo: 2), makeExpense(amount: 5)])
        #expect(since2MonthsAgo.canGoToPreviousPeriod)
        since2MonthsAgo.explorerPeriod = since2MonthsAgo.explorerPeriod.previous().previous()
        #expect(!since2MonthsAgo.canGoToPreviousPeriod)
    }

    @Test("healthScore is nil when no income and no expenses in recent 6 months")
    func healthScoreNilWithoutRecentTransactions() async {
        let vm = await makeVM(transactions: [])
        #expect(vm.healthScore == nil)
    }

    @Test("healthScore is not nil when income exists in recent 6 months")
    func healthScoreNotNilWithRecentIncome() async {
        let income = makeIncome(amount: 1000, monthsAgo: 0)
        let vm = await makeVM(transactions: [income])
        #expect(vm.healthScore != nil)
    }

    @Test("healthScore is not nil when expenses exist in recent 6 months")
    func healthScoreNotNilWithRecentExpense() async {
        let expense = makeExpense(amount: 100, monthsAgo: 0)
        let vm = await makeVM(transactions: [expense])
        #expect(vm.healthScore != nil)
    }
}
}
