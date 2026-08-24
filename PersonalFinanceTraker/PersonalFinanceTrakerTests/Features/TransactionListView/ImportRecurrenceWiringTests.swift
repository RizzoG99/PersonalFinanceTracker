import Testing
import Foundation
import SwiftData
@testable import PersonalFinanceTraker

/// Tests for the view-model wiring of recurring-transaction detection in the import flow.
/// These tests exercise confirmImport(), addSelectedRecurrenceRules(), and cancelImport()
/// to ensure the recurrence suggestions are properly handled in the UI state machine.
@Suite
struct ImportRecurrenceWiringTests {

    @MainActor
    private func makeVM(_ repo: MockTransactionRepository = MockTransactionRepository()) async -> TransactionListViewModel {
        TransactionListViewModel(repo: repo)
    }

    // MARK: - Test 1: Failed import must not navigate to suggestion screen

    @Test @MainActor
    func failedImportDoesNotNavigateToSuggestions() async {
        let repo = MockTransactionRepository()
        // Fail ONLY the batch insert. Blanket `shouldThrow` would trip the earlier `fetchAll`,
        // so confirmImport would early-return at step 5 and never reach the `failCount == 0 &&`
        // branch this test exists to pin.
        repo.addBatchShouldThrow = true
        repo.stubbedTransactions = []
        repo.stubbedCategories = []

        let vm = await makeVM(repo)

        vm.showingImportFlow = true

        // Prepare inputs for import
        let input = TransactionInput(
            timestamp: Date(),
            amount: -100,
            note: "Gym membership",
            category: "Fitness",
            currencyCode: "EUR",
            categoryPersistentId: nil
        )

        // Call confirmImport and await completion
        vm.confirmImport([input])
        await vm.confirmImportTask?.value

        // Assert: import flow should be dismissed, no navigation to suggestions
        // This pins the `failCount == 0 &&` half of the branch condition,
        // which is easy to "simplify" away and would silently swallow import errors.
        #expect(vm.showingImportFlow == false)
        #expect(vm.importNavigationPath.contains(.recurringSuggestions) == false)
        #expect(vm.importError != nil)
        // Resolved through the catalog, not compared to English: these strings are localized
        // now, and a simulator running Italian would fail a literal match.
        #expect(vm.importError == String(localized: "Failed to save \(1) of \(1). Check available storage and try again."))
    }

    // MARK: - Test 2: Successful import WITH suggestions navigates instead of dismissing

    @Test @MainActor
    func successfulImportWithSuggestionsNavigates() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = []
        repo.stubbedCategories = [
            .test(name: "Fitness", type: .expense)
        ]
        repo.shouldThrow = false

        let vm = await makeVM(repo)

        let suggestion = RecurrenceSuggestion(
            frequency: .monthly,
            interval: 1,
            amount: -100,
            note: "Gym membership",
            category: "Fitness",
            currencyCode: "EUR",
            categoryPersistentId: nil,
            occurrenceCount: 3,
            nextDate: Date().addingTimeInterval(86400)
        )
        vm.recurrenceSuggestions = [suggestion]
        vm.selectedSuggestionIds = [suggestion.id]
        vm.showingImportFlow = true

        let input = TransactionInput(
            timestamp: Date(),
            amount: -100,
            note: "Gym membership",
            category: "Fitness",
            currencyCode: "EUR",
            categoryPersistentId: nil
        )

        // Call confirmImport and await completion
        vm.confirmImport([input])
        await vm.confirmImportTask?.value

        // Assert: import flow stays open, navigated to suggestions screen
        #expect(vm.showingImportFlow == true)
        #expect(vm.importNavigationPath.last == .recurringSuggestions)
        #expect(vm.recurrenceSuggestions.map(\.id) == [suggestion.id])
        #expect(vm.importError == nil)
    }

    // MARK: - Test 3: Successful import with NO suggestions dismisses flow

    @Test @MainActor
    func successfulImportWithoutSuggestionsDismisses() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = []
        repo.stubbedCategories = [
            .test(name: "Fitness", type: .expense)
        ]
        repo.shouldThrow = false

        let vm = await makeVM(repo)

        // No recurrence suggestions
        vm.recurrenceSuggestions = []
        vm.selectedSuggestionIds = []
        vm.showingImportFlow = true

        // Prepare inputs for import
        let input = TransactionInput(
            timestamp: Date(),
            amount: -100,
            note: "Gym membership",
            category: "Fitness",
            currencyCode: "EUR",
            categoryPersistentId: nil
        )

        // Call confirmImport and await completion
        vm.confirmImport([input])
        await vm.confirmImportTask?.value

        // Assert: import flow is dismissed, summary message shown (no-regression pin)
        #expect(vm.showingImportFlow == false)
        #expect(vm.importNavigationPath.isEmpty || !vm.importNavigationPath.contains(.recurringSuggestions))
        #expect(vm.importError != nil)
        #expect(vm.importError == String(localized: "Imported \(1) transactions."))
    }

    // MARK: - Test 4: addSelectedRecurrenceRules creates one rule per SELECTED suggestion

    @Test @MainActor
    func addSelectedRecurrenceRulesCreatesOneRulePerSelectedSuggestion() async {
        let repo = MockTransactionRepository()
        repo.stubbedCategories = [
            .test(name: "Fitness", type: .expense),
            .test(name: "Utilities", type: .expense),
            .test(name: "Rent", type: .expense)
        ]

        let vm = await makeVM(repo)

        // Create 3 suggestions
        let fitnessSuggestion = RecurrenceSuggestion(
            frequency: .monthly,
            interval: 1,
            amount: -100,
            note: "Gym",
            category: "Fitness",
            currencyCode: "EUR",
            categoryPersistentId: repo.stubbedCategories[0].persistentId,
            occurrenceCount: 3,
            nextDate: Date().addingTimeInterval(86400)
        )
        let utilitiesSuggestion = RecurrenceSuggestion(
            frequency: .monthly,
            interval: 1,
            amount: -50,
            note: "Electric bill",
            category: "Utilities",
            currencyCode: "EUR",
            categoryPersistentId: repo.stubbedCategories[1].persistentId,
            occurrenceCount: 4,
            nextDate: Date().addingTimeInterval(86400 * 7)
        )
        let rentSuggestion = RecurrenceSuggestion(
            frequency: .monthly,
            interval: 1,
            amount: -1200,
            note: "Rent",
            category: "Rent",
            currencyCode: "EUR",
            categoryPersistentId: repo.stubbedCategories[2].persistentId,
            occurrenceCount: 5,
            nextDate: Date().addingTimeInterval(86400 * 14)
        )

        vm.recurrenceSuggestions = [fitnessSuggestion, utilitiesSuggestion, rentSuggestion]

        // Select only 2 suggestions (fitness and utilities)
        vm.selectedSuggestionIds = [fitnessSuggestion.id, utilitiesSuggestion.id]

        // Call addSelectedRecurrenceRules
        await vm.addSelectedRecurrenceRules()

        // Assert: exactly 2 rules were added
        #expect(repo.addRecurrenceRuleCalls.count == 2)

        // Verify the rules match the selected suggestions
        let addedNotes = Set(repo.addRecurrenceRuleCalls.map(\.note))
        #expect(addedNotes.contains("Gym"))
        #expect(addedNotes.contains("Electric bill"))
        #expect(addedNotes.contains("Rent") == false)
    }

    // MARK: - Test 5: addSelectedRecurrenceRules must NOT materialize occurrences

    @Test @MainActor
    func addSelectedRecurrenceRulesDoesNotMaterializeOccurrences() async {
        let repo = MockTransactionRepository()
        repo.stubbedCategories = [
            .test(name: "Fitness", type: .expense)
        ]

        let vm = await makeVM(repo)

        let suggestion = RecurrenceSuggestion(
            frequency: .monthly,
            interval: 1,
            amount: -100,
            note: "Gym",
            category: "Fitness",
            currencyCode: "EUR",
            categoryPersistentId: repo.stubbedCategories[0].persistentId,
            occurrenceCount: 3,
            nextDate: Date().addingTimeInterval(86400)
        )

        vm.recurrenceSuggestions = [suggestion]
        vm.selectedSuggestionIds = [suggestion.id]

        // Reset any prior calls
        repo.materializeOccurrencesCalls = []

        // Call addSelectedRecurrenceRules
        await vm.addSelectedRecurrenceRules()

        // Assert: materializeOccurrences was NEVER called
        // Rationale: The transaction already exists from the import with nextDate in the future.
        // RecurrenceMaterializationService will pick it up naturally at the next app launch.
        // Materializing here would duplicate the first occurrence, which is already in the database.
        #expect(repo.materializeOccurrencesCalls.isEmpty)
    }

    // MARK: - Test 6: addSelectedRecurrenceRules builds rule with startDate == suggestion.nextDate

    @Test @MainActor
    func addSelectedRecurrenceRulesBuildRuleWithCorrectStartDateAndNoCursor() async {
        let repo = MockTransactionRepository()
        repo.stubbedCategories = [
            .test(name: "Fitness", type: .expense)
        ]

        let vm = await makeVM(repo)

        let nextDate = Date().addingTimeInterval(86400 * 30)
        let suggestion = RecurrenceSuggestion(
            frequency: .monthly,
            interval: 1,
            amount: -100,
            note: "Gym",
            category: "Fitness",
            currencyCode: "EUR",
            categoryPersistentId: repo.stubbedCategories[0].persistentId,
            occurrenceCount: 3,
            nextDate: nextDate
        )

        vm.recurrenceSuggestions = [suggestion]
        vm.selectedSuggestionIds = [suggestion.id]

        // Call addSelectedRecurrenceRules
        await vm.addSelectedRecurrenceRules()

        // Assert: exactly one rule was added
        #expect(repo.addRecurrenceRuleCalls.count == 1)

        let addedRule = repo.addRecurrenceRuleCalls[0]

        // startDate must equal suggestion.nextDate (no past date that could cause backfill)
        #expect(addedRule.startDate == nextDate)

        // lastMaterializedDate must be nil (no cursor that could duplicate first occurrence)
        #expect(addedRule.lastMaterializedDate == nil)
    }

    // MARK: - Test 7: iPad confirms the import and the rules in one shot

    @Test @MainActor
    func confirmImportAddingRecurrenceRulesWritesRulesAndDismisses() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = []
        repo.stubbedCategories = [.test(name: "Fitness", type: .expense)]

        let vm = await makeVM(repo)

        let kept = RecurrenceSuggestion(
            frequency: .monthly, interval: 1, amount: -100, note: "Gym",
            category: "Fitness", currencyCode: "EUR", categoryPersistentId: nil,
            occurrenceCount: 3, nextDate: Date().addingTimeInterval(86400)
        )
        let unchecked = RecurrenceSuggestion(
            frequency: .monthly, interval: 1, amount: -9, note: "Coffee",
            category: "Fitness", currencyCode: "EUR", categoryPersistentId: nil,
            occurrenceCount: 3, nextDate: Date().addingTimeInterval(86400)
        )
        vm.recurrenceSuggestions = [kept, unchecked]
        vm.selectedSuggestionIds = [kept.id]   // the user unchecked "Coffee" on the Recurring tab
        vm.showingImportFlow = true

        vm.confirmImport([
            TransactionInput(timestamp: Date(), amount: -100, note: "Gym",
                             category: "Fitness", currencyCode: "EUR", categoryPersistentId: nil)
        ], addingRecurrenceRules: true)
        await vm.confirmImportTask?.value

        // The iPad flow has no follow-up screen: rules land with the transactions and the sheet closes.
        #expect(repo.addRecurrenceRuleCalls.map(\.note) == ["Gym"])
        #expect(vm.showingImportFlow == false)
        #expect(vm.importNavigationPath.contains(.recurringSuggestions) == false)
        #expect(vm.importError == [String(localized: "Imported \(1) transactions."),
                                   String(localized: "Added \(1) recurring transactions.")].joined(separator: " "))
    }

    // MARK: - Test 8: cancelImport clears all import state

    @Test @MainActor
    func cancelImportClearsAllImportState() async {
        let repo = MockTransactionRepository()
        let vm = await makeVM(repo)

        // Set up rich import state
        vm.recurrenceSuggestions = [
            RecurrenceSuggestion(
                frequency: .monthly,
                interval: 1,
                amount: -100,
                note: "Recurring",
                category: "Test",
                currencyCode: "EUR",
                categoryPersistentId: nil,
                occurrenceCount: 3,
                nextDate: Date()
            )
        ]
        vm.selectedSuggestionIds = Set(vm.recurrenceSuggestions.map(\.id))
        vm.importedTransactionCount = 42
        vm.showingImportFlow = true

        // Call cancelImport
        vm.cancelImport()

        // Assert: all import state is cleared
        #expect(vm.recurrenceSuggestions.isEmpty)
        #expect(vm.selectedSuggestionIds.isEmpty)
        #expect(vm.importedTransactionCount == 0)
        #expect(vm.showingImportFlow == false)
    }
}
