//
//  ImportCategoryNameTests.swift
//  PersonalFinanceTrakerTests
//
//  #232: an imported row must carry the *mapped* app category's name, not the CSV's, because
//  the list, budgets, charts and the category filter all key on that string.
//

import Foundation
import SwiftData
import Testing
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct ImportCategoryNameTests {

    private func makeActor() -> (TransactionActor, ModelContainer) {
        let schema = Schema([TransactionModel.self, CategoryModel.self, GoalModel.self, RecurrenceRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return (TransactionActor(modelContainer: container), container)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "ImportCategoryNameTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @MainActor
    private func mappedInputs(csv: String, categories: [CategorySnapshot], selections: [String: String]) async -> [TransactionInput] {
        let vm = TransactionListViewModel(repo: MockTransactionRepository())
        let lines = csv.split(separator: "\n").map(String.init)
        vm.csvFile = CSVFile(
            headers: lines[0].split(separator: ";").map(String.init),
            delimiter: ";",
            lines: lines.dropFirst().enumerated().map { (lineNumber: $0.offset + 2, text: $0.element) }
        )
        vm.columnMapping = ColumnMapping(
            dateColumn: "Date", amountColumn: "Amount", categoryColumn: "Category", noteColumn: "Note",
            dateFormat: "yyyy-MM-dd"
        )
        vm.availableCategories = categories
        vm.categoryResolutionSelections = selections
        await vm.applyMapping()
        return vm.mappedRows.compactMap(\.input)
    }

    @Test @MainActor func mappedRowCarriesAppCategoryName() async {
        let sanita = CategorySnapshot.test(name: "Sanità")
        let inputs = await mappedInputs(
            csv: "Date;Amount;Category;Note\n2026-10-01;-49;Salute e benessere;Psicologa",
            categories: [sanita],
            selections: ["Salute e benessere": sanita.id.uuidString]
        )
        #expect(inputs.first?.category == "Sanità")
        #expect(inputs.first?.categoryPersistentId == sanita.persistentId)
    }

    @Test @MainActor func blankCSVCategoryLinksToOtherOfMatchingType() async {
        let otherExpense = CategorySnapshot.test(name: "Other", type: .expense)
        let otherIncome = CategorySnapshot.test(name: "Other", type: .income)
        let inputs = await mappedInputs(
            csv: "Date;Amount;Category;Note\n2026-10-01;-5;;Coffee\n2026-10-02;20;;Refund",
            categories: [otherExpense, otherIncome],
            selections: [:]
        )
        #expect(inputs.count == 2)
        #expect(inputs[0].categoryPersistentId == otherExpense.persistentId)
        #expect(inputs[1].categoryPersistentId == otherIncome.persistentId)
    }

    @Test @MainActor func newCategoryRenamedInDraftCarriesDraftName() async throws {
        let (actor, _) = makeActor()
        let vm = TransactionListViewModel(repo: actor)
        vm.load()
        await vm.loadTask?.value

        let csvCategory = "Ristoranti e bar"
        vm.categoryResolutionSelections = [csvCategory: "__new__"]
        vm.pendingCategoryDrafts = [
            csvCategory: ImportCategoryDraft(
                csvCategory: csvCategory, name: "Ristoranti", type: .expense,
                systemImage: "fork.knife", colorToken: "categoryOrange"
            )
        ]
        vm.confirmImport([TransactionInput(
            timestamp: Date(), amount: -54.10, note: "Cena", category: csvCategory, currencyCode: "EUR"
        )])
        await vm.importTask?.value

        let imported = try #require(try await actor.fetchAll().first { $0.note == "Cena" })
        #expect(imported.category == "Ristoranti")
        #expect(imported.categoryId != nil)
    }

    @Test @MainActor func recurrenceRuleForNewCategoryLinksToCreatedCategory() async throws {
        let (actor, _) = makeActor()
        let vm = TransactionListViewModel(repo: actor)
        vm.load()
        await vm.loadTask?.value

        let csvCategory = "Salute e benessere"
        vm.categoryResolutionSelections = [csvCategory: "__new__"]
        vm.pendingCategoryDrafts = [
            csvCategory: ImportCategoryDraft(
                csvCategory: csvCategory, name: "Sanità", type: .expense,
                systemImage: "cross.case", colorToken: "categoryRed"
            )
        ]
        let suggestion = RecurrenceSuggestion(
            frequency: .monthly, interval: 1, amount: -49, note: "Psicologa",
            category: csvCategory, currencyCode: "EUR", categoryPersistentId: nil,
            occurrenceCount: 3, nextDate: Date().addingTimeInterval(86400), occurrenceDates: [Date()]
        )
        vm.recurrenceSuggestions = [suggestion]
        vm.selectedSuggestionIds = [suggestion.id]
        vm.confirmImport(
            [TransactionInput(timestamp: Date(), amount: -49, note: "Psicologa", category: csvCategory, currencyCode: "EUR")],
            addingRecurrenceRules: true
        )
        await vm.importTask?.value

        let rule = try #require(try await actor.fetchActiveRecurrenceRules().first)
        #expect(rule.category == "Sanità")
        #expect(rule.categoryId != nil)
    }

    // MARK: - One-time repair of rows imported before the fix

    @Test func repairRewritesStaleNamesOnceAndSkipsUnlinkedRows() async throws {
        let (actor, container) = makeActor()
        let context = ModelContext(container)
        let sanita = CategoryModel(name: "Sanità", systemImage: "cross.case", type: .expense, colorToken: "categoryRed")
        context.insert(sanita)
        let stale = (0..<5000).map { i in
            TransactionModel(timestamp: Date(), amount: -1, note: "Psicologa \(i)", category: "Salute e benessere", categoryModel: sanita)
        }
        stale.forEach(context.insert)
        context.insert(TransactionModel(timestamp: Date(), amount: -2, note: "Unlinked", category: "Gym & Fitness"))
        try context.save()

        let defaults = freshDefaults()
        let saves = CategoryRepairSaveCounter(container: container)
        let result = try await actor.repairCategoryNamesMeasuringCPU(defaults: defaults)

        #expect(result.fixed == 5000)
        // Protect the single-save contract directly. A wall-clock budget across the actor
        // call includes unrelated scheduling/storage contention in the full suite.
        #expect(saves.count == 1)
        #expect(result.cpuTime < .seconds(5))
        let all = try await actor.fetchAll()
        #expect(all.filter { $0.category == "Sanità" }.count == 5000)
        #expect(all.first { $0.note == "Unlinked" }?.category == "Gym & Fitness")

        #expect(try await actor.repairImportedCategoryNames(defaults: defaults) == 0)
        #expect(saves.count == 1) // A completed repair must not save again.
    }

    /// A rule stamps its own `category` on every occurrence it materializes, so a stale rule
    /// would keep producing old-name rows after the one-time repair has run.
    @Test func repairRewritesStaleRecurrenceRuleNames() async throws {
        let (actor, container) = makeActor()
        let context = ModelContext(container)
        let cat = CategoryModel(name: "Sanità", systemImage: "cross.case", type: .expense, colorToken: "categoryRed")
        context.insert(cat)
        context.insert(RecurrenceRule(
            frequency: .monthly, interval: 1, startDate: Date(), amount: -49, note: "Psicologa",
            category: "Salute e benessere", currencyCode: "EUR", categoryModel: cat
        ))
        try context.save()

        #expect(try await actor.repairImportedCategoryNames(defaults: freshDefaults()) == 1)
        #expect(try await actor.fetchActiveRecurrenceRules().first?.category == "Sanità")
    }

    @Test func repairIsIdempotentWhenFlagIsReset() async throws {
        let (actor, container) = makeActor()
        let context = ModelContext(container)
        let cat = CategoryModel(name: "Ristoranti", systemImage: "fork.knife", type: .expense, colorToken: "categoryOrange")
        context.insert(cat)
        context.insert(TransactionModel(timestamp: Date(), amount: -10, note: "Bar", category: "Ristoranti e bar", categoryModel: cat))
        try context.save()

        #expect(try await actor.repairImportedCategoryNames(defaults: freshDefaults()) == 1)
        // A fresh flag (e.g. a crash before it was written) must find nothing left to do.
        #expect(try await actor.repairImportedCategoryNames(defaults: freshDefaults()) == 0)
    }
}

/// Keep the CPU interval inside the actor's synchronous work; no await crosses it.
private extension TransactionActor {
    func repairCategoryNamesMeasuringCPU(defaults: UserDefaults) throws -> (fixed: Int, cpuTime: Duration) {
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        let fixed = try repairImportedCategoryNames(defaults: defaults)
        let elapsed = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start
        return (fixed, .nanoseconds(Int64(elapsed)))
    }
}

/// didSave is synchronous on the writer's thread; every count access uses the lock.
private final class CategoryRepairSaveCounter: @unchecked Sendable {
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
