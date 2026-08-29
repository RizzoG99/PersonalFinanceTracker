import Testing
import Foundation
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct EditAddTransactionViewModelTests {

    private func expenseCat() -> CategorySnapshot {
        .test(name: "Food", systemImage: "fork.knife", type: .expense)
    }

    private func incomeCat() -> CategorySnapshot {
        .test(name: "Salary", systemImage: "dollarsign", type: .income)
    }

    @MainActor
    private func makeVM(editingItem: TransactionSnapshot? = nil) -> EditAddTransactionViewModel {
        EditAddTransactionViewModel(editingItem: editingItem, repo: MockTransactionRepository())
    }

    @Test @MainActor func widgetDraftKeepsTheInitialReviewFormUnfocused() {
        let draft = TransactionDraft(
            amount: 12.5,
            transactionType: .expense,
            categoryName: "Food",
            note: "Lunch"
        )

        let vm = EditAddTransactionViewModel(draft: draft, repo: MockTransactionRepository())

        #expect(vm.amount == 12.5)
        #expect(vm.transactionType == .expense)
        #expect(vm.shouldAutoFocusAmount == false)
    }

    // MARK: - Receipt scan

    /// Reproduces the category race: `setTransactionViewModel()` loads the categories in its own
    /// `Task`, and a scan applied straight afterwards — which is exactly what the Home/Activity
    /// shortcut does on `onAppear` — used to infer against an empty pool and fill everything except
    /// the category. Fails without the `await loadTask?.value` in `applyReceiptScan`.
    @Test @MainActor func scanAppliedRightAfterOpeningStillGetsACategory() async {
        let repo = MockTransactionRepository()
        repo.stubbedCategories = [expenseCat(), incomeCat()]
        let vm = EditAddTransactionViewModel(editingItem: nil, repo: repo)

        // No `await` between these two on purpose — the bug only appears when the scan does not
        // give the loader a chance to finish first.
        vm.setTransactionViewModel()
        var scan = ReceiptScan()
        scan.total = 5.00
        scan.merchant = "Cremeria"
        await vm.applyReceiptScan(scan, learnedMerchants: [:])

        #expect(vm.selectedCategory != nil, "a scan must always leave the required category filled")
    }

    // MARK: isFormValid

    // Name is optional: a blank/whitespace name is valid as long as amount + category are set
    // (the list falls back to the localized category name for display).
    @Test @MainActor func validWhenNameIsEmpty() async throws {
        let vm = makeVM()
        vm.transactionName = ""
        vm.amount = 50
        vm.selectedCategory = expenseCat()
        #expect(vm.isFormValid == true)
    }

    @Test @MainActor func validWhenNameIsWhitespaceOnly() async throws {
        let vm = makeVM()
        vm.transactionName = "   "
        vm.amount = 50
        vm.selectedCategory = expenseCat()
        #expect(vm.isFormValid == true)
    }

    @Test @MainActor func invalidWhenAmountIsZero() async throws {
        let vm = makeVM()
        vm.transactionName = "Lunch"
        vm.amount = 0
        vm.selectedCategory = expenseCat()
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func invalidWhenAmountIsNegative() async throws {
        let vm = makeVM()
        vm.transactionName = "Lunch"
        vm.amount = -50
        vm.selectedCategory = expenseCat()
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func invalidWhenNoCategoryForExpense() async throws {
        let vm = makeVM()
        vm.transactionName = "Lunch"
        vm.amount = 50
        vm.transactionType = .expense
        vm.selectedCategory = nil
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func invalidWhenNoCategoryForIncome() async throws {
        let vm = makeVM()
        vm.transactionName = "Salary"
        vm.amount = 2000
        vm.transactionType = .income
        vm.selectedCategory = nil
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func invalidWhenNoGoalForTransfer() async throws {
        let vm = makeVM()
        vm.transactionName = "Transfer"
        vm.amount = 500
        vm.transactionType = .transfer
        vm.selectedGoal = nil
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func invalidWhenDateIsInFuture() async throws {
        let vm = makeVM()
        vm.transactionName = "Lunch"
        vm.amount = 50
        vm.transactionType = .expense
        vm.selectedCategory = expenseCat()
        vm.date = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func validWithAllRequiredFieldsSetForExpense() async throws {
        let vm = makeVM()
        vm.transactionName = "Lunch"
        vm.amount = 50
        vm.transactionType = .expense
        vm.selectedCategory = expenseCat()
        vm.date = Date()
        #expect(vm.isFormValid == true)
    }

    @Test @MainActor func validWithAllRequiredFieldsSetForIncome() async throws {
        let vm = makeVM()
        vm.transactionName = "Salary"
        vm.amount = 2000
        vm.transactionType = .income
        vm.selectedCategory = incomeCat()
        vm.date = Date()
        #expect(vm.isFormValid == true)
    }

    @Test @MainActor func selectCreatedCategoryAddsAndSelectsIt() async throws {
        let vm = makeVM()
        let original = expenseCat()
        let created = CategorySnapshot.test(name: "Books", systemImage: "book.fill", type: .expense)
        vm.availableCategories = [original]

        vm.selectCreatedCategory(created)

        #expect(vm.availableCategories.contains(created))
        #expect(vm.selectedCategory == created)
    }

    @Test @MainActor func validWithAllRequiredFieldsSetForTransfer() async throws {
        let vm = makeVM()
        vm.transactionName = "Transfer"
        vm.amount = 500
        vm.transactionType = .transfer
        vm.selectedGoal = .test(name: "Savings", targetAmount: 10000)
        vm.date = Date()
        #expect(vm.isFormValid == true)
    }

    // MARK: availableTypes (Transfer hidden without goals)

    @Test @MainActor func availableTypesHidesTransferWhenNoGoals() async throws {
        let vm = makeVM()
        vm.availableGoals = []
        #expect(!vm.availableTypes.contains(.transfer))
        #expect(vm.availableTypes.contains(.income))
        #expect(vm.availableTypes.contains(.expense))
    }

    @Test @MainActor func availableTypesIncludesTransferWhenGoalsExist() async throws {
        let vm = makeVM()
        vm.availableGoals = [.test(name: "Savings", targetAmount: 1000)]
        #expect(vm.availableTypes.contains(.transfer))
    }

    @Test @MainActor func availableTypesKeepsTransferWhenAlreadySelected() async throws {
        let vm = makeVM()
        vm.availableGoals = []
        vm.transactionType = .transfer
        // Never hide the currently-selected type (e.g. editing an existing transfer).
        #expect(vm.availableTypes.contains(.transfer))
    }

    // MARK: formattedDate

    @Test @MainActor func formattedDateIsToday() async throws {
        let vm = makeVM()
        vm.date = Date()
        // Compared against the same localized lookup the view model uses, not a hardcoded
        // English literal, so this doesn't depend on the test device's language (see
        // git history for the locale investigation this replaced).
        #expect(vm.formattedDate == String(localized: "Today"))
    }

    @Test @MainActor func formattedDateIsYesterday() async throws {
        let vm = makeVM()
        vm.date = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        #expect(vm.formattedDate == String(localized: "Yesterday"))
    }

    @Test @MainActor func formattedDateIsNeitherTodayNorYesterdayForOlderDate() async throws {
        let vm = makeVM()
        vm.date = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        #expect(vm.formattedDate != "Today")
        #expect(vm.formattedDate != "Yesterday")
        #expect(!vm.formattedDate.isEmpty)
    }

    @Test @MainActor func formattedDateForVeryOldDate() async throws {
        let vm = makeVM()
        let components = DateComponents(year: 2020, month: 1, day: 15)
        vm.date = Calendar.current.date(from: components)!
        #expect(vm.formattedDate != "Today")
        #expect(vm.formattedDate != "Yesterday")
        #expect(vm.formattedDate.contains("2020") || vm.formattedDate.contains("Jan"))
    }

    // MARK: filteredCategories

    @Test @MainActor func filteredCategoriesMatchesExpenseType() async throws {
        let vm = makeVM()
        vm.availableCategories = [expenseCat(), incomeCat()]
        vm.transactionType = .expense
        #expect(vm.filteredCategories.count == 1)
        #expect(vm.filteredCategories.first?.name == "Food")
    }

    @Test @MainActor func filteredCategoriesMatchesIncomeType() async throws {
        let vm = makeVM()
        vm.availableCategories = [expenseCat(), incomeCat()]
        vm.transactionType = .income
        #expect(vm.filteredCategories.count == 1)
        #expect(vm.filteredCategories.first?.name == "Salary")
    }

    @Test @MainActor func filteredCategoriesIsEmptyWhenNoCategoriesMatch() async throws {
        let vm = makeVM()
        vm.availableCategories = [expenseCat()]
        vm.transactionType = .income
        #expect(vm.filteredCategories.isEmpty)
    }

    @Test @MainActor func filteredCategoriesReturnsMultipleMatching() async throws {
        let vm = makeVM()
        vm.availableCategories = [
            .test(name: "Food", systemImage: "fork.knife", type: .expense),
            .test(name: "Entertainment", systemImage: "film", type: .expense),
            incomeCat(),
        ]
        vm.transactionType = .expense
        #expect(vm.filteredCategories.count == 2)
    }

    // MARK: buildInput

    @Test @MainActor func buildInputCreatesNegativeAmountForExpense() async throws {
        let vm = makeVM()
        vm.transactionName = "Lunch"
        vm.amount = 25
        vm.transactionType = .expense
        vm.selectedCategory = expenseCat()
        let input = vm.buildInput()
        #expect(input?.amount == -25)
        #expect(input?.note == "Lunch")
    }

    @Test @MainActor func buildInputCreatesPositiveAmountForIncome() async throws {
        let vm = makeVM()
        vm.transactionName = "Salary"
        vm.amount = 2000
        vm.transactionType = .income
        vm.selectedCategory = incomeCat()
        let input = vm.buildInput()
        #expect(input?.amount == 2000)
    }

    @Test @MainActor func buildInputReturnsNilWithNoCategory() async throws {
        let vm = makeVM()
        vm.transactionName = "Lunch"
        vm.amount = 25
        vm.transactionType = .expense
        vm.selectedCategory = nil
        #expect(vm.buildInput() == nil)
    }

    @Test @MainActor func buildInputPreservesCategory() async throws {
        let vm = makeVM()
        vm.transactionName = "Lunch"
        vm.amount = 25
        vm.transactionType = .expense
        let cat = expenseCat()
        vm.selectedCategory = cat
        let input = vm.buildInput()
        #expect(input?.category == "Food")
        #expect(input?.categoryPersistentId == cat.persistentId)
    }

    @Test @MainActor func buildInputForTransferWithGoal() async throws {
        let vm = makeVM()
        vm.transactionName = "Transfer"
        vm.amount = 500
        vm.transactionType = .transfer
        let goal = GoalSnapshot.test(name: "Savings", targetAmount: 10000)
        vm.selectedGoal = goal
        let input = vm.buildInput()
        #expect(input?.amount == -500)
        #expect(input?.goalId == goal.id)
    }

    @Test @MainActor func buildInputForTransferReturnsNilWithoutGoal() async throws {
        let vm = makeVM()
        vm.transactionName = "Transfer"
        vm.amount = 500
        vm.transactionType = .transfer
        vm.selectedGoal = nil
        #expect(vm.buildInput() == nil)
    }

    // MARK: init(editingItem:)

    @Test @MainActor func initWithNegativeTransactionSetsExpense() async throws {
        let snap = TransactionSnapshot.test(amount: -75, note: "Dinner", category: "Food")
        let vm = makeVM(editingItem: snap)
        #expect(vm.transactionName == "Dinner")
        #expect(vm.amount == 75)
        #expect(vm.transactionType == .expense)
    }

    @Test @MainActor func initWithPositiveTransactionSetsIncome() async throws {
        let snap = TransactionSnapshot.test(amount: 3000, note: "Salary", category: "Income")
        let vm = makeVM(editingItem: snap)
        #expect(vm.transactionName == "Salary")
        #expect(vm.amount == 3000)
        #expect(vm.transactionType == .income)
    }

    @Test @MainActor func initWithGoalIdSetsTransfer() async throws {
        let snap = TransactionSnapshot.test(amount: -500, note: "Transfer", category: "Goal", goalId: UUID())
        let vm = makeVM(editingItem: snap)
        #expect(vm.transactionType == .transfer)
        #expect(vm.transactionName == "Transfer")
    }

    @Test @MainActor func initPreservesTimestamp() async throws {
        let date = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let snap = TransactionSnapshot.test(timestamp: date, amount: -75, note: "Dinner", category: "Food")
        let vm = makeVM(editingItem: snap)
        #expect(vm.date == date)
    }

    @Test @MainActor func initPreservesCurrencyCode() async throws {
        let snap = TransactionSnapshot.test(amount: -75, note: "Dinner", category: "Food", currencyCode: "GBP")
        let vm = makeVM(editingItem: snap)
        #expect(vm.currencyCode == "GBP")
    }

    @Test @MainActor func initStoresEditingItem() async throws {
        let snap = TransactionSnapshot.test(amount: -75, note: "Dinner", category: "Food")
        let vm = makeVM(editingItem: snap)
        #expect(vm.editingItem?.id == snap.id)
    }

    // MARK: resetForm

    @Test @MainActor func resetFormClearsNameAndAmount() async throws {
        let vm = makeVM()
        vm.transactionName = "Test"
        vm.amount = 100
        vm.resetForm()
        #expect(vm.transactionName == "")
        #expect(vm.amount == 0)
    }

    @Test @MainActor func resetFormClearsCategory() async throws {
        let vm = makeVM()
        vm.selectedCategory = expenseCat()
        vm.resetForm()
        #expect(vm.selectedCategory == nil)
    }

    @Test @MainActor func resetFormClearsGoal() async throws {
        let vm = makeVM()
        vm.selectedGoal = .test(name: "Savings", targetAmount: 10000)
        vm.resetForm()
        #expect(vm.selectedGoal == nil)
    }

    @Test @MainActor func resetFormResetsTypeToExpense() async throws {
        let vm = makeVM()
        vm.transactionType = .income
        vm.resetForm()
        #expect(vm.transactionType == .expense)
    }

    @Test @MainActor func resetFormResetsDateToNow() async throws {
        let vm = makeVM()
        vm.date = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let beforeReset = Date()
        vm.resetForm()
        let afterReset = Date()
        #expect(vm.date >= beforeReset && vm.date <= afterReset)
    }

    @Test @MainActor func addAnotherDefaultsToFalse() async throws {
        let vm = makeVM()
        #expect(vm.addAnother == false)
    }

    @Test @MainActor func resetFormPreservesAddAnother() async throws {
        let vm = makeVM()
        vm.addAnother = true
        vm.transactionName = "Coffee"
        vm.amount = 3
        vm.resetForm()
        #expect(vm.addAnother == true)      // control flag survives across saves
        #expect(vm.transactionName == "")   // form fields still cleared
        #expect(vm.amount == 0)
    }

    @Test @MainActor func isFormValidIsFalseAfterReset() async throws {
        let vm = makeVM()
        vm.transactionName = "Coffee"
        vm.amount = 3
        vm.selectedCategory = expenseCat()
        vm.resetForm()
        #expect(vm.isFormValid == false)    // blank form can't be re-saved
    }

    // MARK: default initialization

    @Test @MainActor func initDefaultCreatesNilEditingItem() async throws {
        let vm = makeVM()
        #expect(vm.editingItem == nil)
    }

    @Test @MainActor func initDefaultSetsExpenseType() async throws {
        let vm = makeVM()
        #expect(vm.transactionType == .expense)
    }

    @Test @MainActor func initDefaultSetsEmptyName() async throws {
        let vm = makeVM()
        #expect(vm.transactionName == "")
    }

    @Test @MainActor func initDefaultSetsZeroAmount() async throws {
        let vm = makeVM()
        #expect(vm.amount == 0)
    }

    @Test @MainActor func initDefaultSetsEUR() async throws {
        let vm = makeVM()
        #expect(vm.currencyCode == "EUR")
    }

    @Test @MainActor func initDefaultSetsEmptyCategories() async throws {
        let vm = makeVM()
        #expect(vm.availableCategories.isEmpty)
    }

    // MARK: - Recurrence (create-time)

    @Test @MainActor func buildRecurrenceRuleInputIsNilWhenNotRecurring() async throws {
        let vm = makeVM()
        vm.transactionName = "Rent"
        vm.amount = 1200
        vm.selectedCategory = expenseCat()
        vm.isRecurring = false
        #expect(vm.buildRecurrenceRuleInput() == nil)
    }

    @Test @MainActor func buildRecurrenceRuleInputIsNilForTransfers() async throws {
        let vm = makeVM()
        vm.transactionName = "To savings"
        vm.amount = 200
        vm.transactionType = .transfer
        vm.selectedGoal = .test(name: "Vacation", targetAmount: 1000)
        vm.isRecurring = true
        #expect(vm.buildRecurrenceRuleInput() == nil)
    }

    @Test @MainActor func buildRecurrenceRuleInputMatchesFormWhenRecurring() async throws {
        let vm = makeVM()
        vm.transactionName = "Rent"
        vm.amount = 1200
        vm.transactionType = .expense
        vm.selectedCategory = expenseCat()
        vm.isRecurring = true
        vm.recurrenceFrequency = .monthly
        vm.recurrenceInterval = 1

        let ruleInput = try #require(vm.buildRecurrenceRuleInput())
        #expect(ruleInput.frequency == .monthly)
        #expect(ruleInput.interval == 1)
        #expect(ruleInput.amount == -1200)
        #expect(ruleInput.category == "Food")
    }

    @Test @MainActor func saveRecurringTransactionCreatesRuleAndMaterializesFirstOccurrence() async throws {
        let mock = MockTransactionRepository()
        let vm = EditAddTransactionViewModel(repo: mock)
        vm.transactionName = "Rent"
        vm.amount = 1200
        vm.selectedCategory = expenseCat()
        vm.isRecurring = true
        vm.recurrenceFrequency = .monthly

        try await vm.saveRecurringTransaction()

        #expect(mock.addRecurrenceRuleCalls.count == 1)
        #expect(mock.materializeOccurrencesCalls.count == 1)
        let call = mock.materializeOccurrencesCalls[0]
        #expect(call.ruleId == mock.addRecurrenceRuleCalls[0].id)
        #expect(call.inputs.count == 1)
        #expect(call.inputs[0].timestamp == mock.addRecurrenceRuleCalls[0].startDate)
    }
}

extension EditAddTransactionViewModelTests {
    @Test @MainActor func buildRecurrenceRuleInputPreservingKeepsCadenceAndUpdatesTemplate() async throws {
        let originalStart = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01
        let existingRule = RecurrenceRuleSnapshot.test(
            frequency: .yearly, interval: 2, startDate: originalStart, amount: -1200, category: "Housing"
        )
        let vm = makeVM()
        vm.transactionName = "Rent (increased)"
        vm.amount = 1500
        vm.selectedCategory = expenseCat()

        let result = try #require(vm.buildRecurrenceRuleInput(preserving: existingRule))
        #expect(result.id == existingRule.id)
        #expect(result.frequency == .yearly)
        #expect(result.interval == 2)
        #expect(result.startDate == originalStart)
        #expect(result.amount == -1500)
        #expect(result.note == "Rent (increased)")
    }
}
