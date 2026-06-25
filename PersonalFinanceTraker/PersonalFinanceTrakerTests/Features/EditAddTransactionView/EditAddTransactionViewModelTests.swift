import Testing
import Foundation
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct EditAddTransactionViewModelTests {

    private func expenseCat() -> CategoryModel {
        CategoryModel(name: "Food", systemImage: "fork.knife", type: .expense)
    }

    private func incomeCat() -> CategoryModel {
        CategoryModel(name: "Salary", systemImage: "dollarsign", type: .income)
    }

    // MARK: isFormValid

    @Test @MainActor func invalidWhenNameIsEmpty() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = ""
        vm.amount = 50
        vm.selectedCategory = expenseCat()
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func invalidWhenNameIsWhitespaceOnly() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "   "
        vm.amount = 50
        vm.selectedCategory = expenseCat()
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func invalidWhenAmountIsZero() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Lunch"
        vm.amount = 0
        vm.selectedCategory = expenseCat()
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func invalidWhenAmountIsNegative() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Lunch"
        vm.amount = -50
        vm.selectedCategory = expenseCat()
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func invalidWhenNoCategoryForExpense() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Lunch"
        vm.amount = 50
        vm.transactionType = .expense
        vm.selectedCategory = nil
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func invalidWhenNoCategoryForIncome() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Salary"
        vm.amount = 2000
        vm.transactionType = .income
        vm.selectedCategory = nil
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func invalidWhenNoGoalForTransfer() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Transfer"
        vm.amount = 500
        vm.transactionType = .transfer
        vm.selectedGoal = nil
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func invalidWhenDateIsInFuture() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Lunch"
        vm.amount = 50
        vm.transactionType = .expense
        vm.selectedCategory = expenseCat()
        vm.date = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        #expect(vm.isFormValid == false)
    }

    @Test @MainActor func validWithAllRequiredFieldsSetForExpense() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Lunch"
        vm.amount = 50
        vm.transactionType = .expense
        vm.selectedCategory = expenseCat()
        vm.date = Date()
        #expect(vm.isFormValid == true)
    }

    @Test @MainActor func validWithAllRequiredFieldsSetForIncome() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Salary"
        vm.amount = 2000
        vm.transactionType = .income
        vm.selectedCategory = incomeCat()
        vm.date = Date()
        #expect(vm.isFormValid == true)
    }

    @Test @MainActor func validWithAllRequiredFieldsSetForTransfer() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Transfer"
        vm.amount = 500
        vm.transactionType = .transfer
        let goal = GoalModel(name: "Savings", targetAmount: 10000, deadline: Date())
        vm.selectedGoal = goal
        vm.date = Date()
        #expect(vm.isFormValid == true)
    }

    // MARK: formattedDate

    @Test @MainActor func formattedDateIsToday() async throws {
        let vm = EditAddTransactionViewModel()
        vm.date = Date()
        #expect(vm.formattedDate == "Today")
    }

    @Test @MainActor func formattedDateIsYesterday() async throws {
        let vm = EditAddTransactionViewModel()
        vm.date = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        #expect(vm.formattedDate == "Yesterday")
    }

    @Test @MainActor func formattedDateIsNeitherTodayNorYesterdayForOlderDate() async throws {
        let vm = EditAddTransactionViewModel()
        vm.date = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        #expect(vm.formattedDate != "Today")
        #expect(vm.formattedDate != "Yesterday")
        #expect(!vm.formattedDate.isEmpty)
    }

    @Test @MainActor func formattedDateForVeryOldDate() async throws {
        let vm = EditAddTransactionViewModel()
        let components = DateComponents(year: 2020, month: 1, day: 15)
        vm.date = Calendar.current.date(from: components)!
        #expect(vm.formattedDate != "Today")
        #expect(vm.formattedDate != "Yesterday")
        #expect(vm.formattedDate.contains("2020") || vm.formattedDate.contains("Jan"))
    }

    // MARK: filteredCategories

    @Test @MainActor func filteredCategoriesMatchesExpenseType() async throws {
        let vm = EditAddTransactionViewModel()
        vm.availableCategories = [expenseCat(), incomeCat()]
        vm.transactionType = .expense
        #expect(vm.filteredCategories.count == 1)
        #expect(vm.filteredCategories.first?.name == "Food")
    }

    @Test @MainActor func filteredCategoriesMatchesIncomeType() async throws {
        let vm = EditAddTransactionViewModel()
        vm.availableCategories = [expenseCat(), incomeCat()]
        vm.transactionType = .income
        #expect(vm.filteredCategories.count == 1)
        #expect(vm.filteredCategories.first?.name == "Salary")
    }

    @Test @MainActor func filteredCategoriesIsEmptyWhenNoCategoriesMatch() async throws {
        let vm = EditAddTransactionViewModel()
        vm.availableCategories = [expenseCat()]
        vm.transactionType = .income
        #expect(vm.filteredCategories.isEmpty)
    }

    @Test @MainActor func filteredCategoriesReturnsMultipleMatching() async throws {
        let vm = EditAddTransactionViewModel()
        let food = CategoryModel(name: "Food", systemImage: "fork.knife", type: .expense)
        let entertainment = CategoryModel(name: "Entertainment", systemImage: "film", type: .expense)
        vm.availableCategories = [food, entertainment, incomeCat()]
        vm.transactionType = .expense
        #expect(vm.filteredCategories.count == 2)
    }

    // MARK: getTransactionData

    @Test @MainActor func getTransactionDataCreatesNegativeAmountForExpense() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Lunch"
        vm.amount = 25
        vm.transactionType = .expense
        vm.selectedCategory = expenseCat()
        let tx = vm.getTransactionData()
        #expect(tx?.amount == -25)
        #expect(tx?.note == "Lunch")
    }

    @Test @MainActor func getTransactionDataCreatesPositiveAmountForIncome() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Salary"
        vm.amount = 2000
        vm.transactionType = .income
        vm.selectedCategory = incomeCat()
        let tx = vm.getTransactionData()
        #expect(tx?.amount == 2000)
    }

    @Test @MainActor func getTransactionDataReturnsNilWithNoCategory() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Lunch"
        vm.amount = 25
        vm.transactionType = .expense
        vm.selectedCategory = nil
        #expect(vm.getTransactionData() == nil)
    }

    @Test @MainActor func getTransactionDataPreservesCategory() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Lunch"
        vm.amount = 25
        vm.transactionType = .expense
        let cat = expenseCat()
        vm.selectedCategory = cat
        let tx = vm.getTransactionData()
        #expect(tx?.category == "Food")
        #expect(tx?.categoryModel?.name == "Food")
    }

    @Test @MainActor func getTransactionDataForTransferWithGoal() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Transfer"
        vm.amount = 500
        vm.transactionType = .transfer
        let goal = GoalModel(name: "Savings", targetAmount: 10000, deadline: Date())
        vm.selectedGoal = goal
        let tx = vm.getTransactionData()
        #expect(tx?.amount == -500)
        #expect(tx?.goalId == goal.id)
    }

    @Test @MainActor func getTransactionDataForTransferReturnsNilWithoutGoal() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Transfer"
        vm.amount = 500
        vm.transactionType = .transfer
        vm.selectedGoal = nil
        #expect(vm.getTransactionData() == nil)
    }

    @Test @MainActor func getTransactionDataResetsFormAfterSuccess() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Lunch"
        vm.amount = 25
        vm.transactionType = .expense
        vm.selectedCategory = expenseCat()
        _ = vm.getTransactionData()
        #expect(vm.transactionName == "")
        #expect(vm.amount == 0)
        #expect(vm.selectedCategory == nil)
    }

    // MARK: init(transaction:)

    @Test @MainActor func initWithNegativeTransactionSetsExpense() async throws {
        let tx = TransactionModel(timestamp: Date(), amount: -75, note: "Dinner", category: "Food")
        let vm = EditAddTransactionViewModel(transaction: tx)
        #expect(vm.transactionName == "Dinner")
        #expect(vm.amount == 75)
        #expect(vm.transactionType == .expense)
    }

    @Test @MainActor func initWithPositiveTransactionSetsIncome() async throws {
        let tx = TransactionModel(timestamp: Date(), amount: 3000, note: "Salary", category: "Income")
        let vm = EditAddTransactionViewModel(transaction: tx)
        #expect(vm.transactionName == "Salary")
        #expect(vm.amount == 3000)
        #expect(vm.transactionType == .income)
    }

    @Test @MainActor func initWithGoalIdSetsTransfer() async throws {
        let goalId = UUID()
        let tx = TransactionModel(timestamp: Date(), amount: -500, note: "Transfer", category: "Goal", goalId: goalId)
        let vm = EditAddTransactionViewModel(transaction: tx)
        #expect(vm.transactionType == .transfer)
        #expect(vm.transactionName == "Transfer")
    }

    @Test @MainActor func initWithZeroAmountSetsIncome() async throws {
        let tx = TransactionModel(timestamp: Date(), amount: 0, note: "Zero", category: "Food")
        let vm = EditAddTransactionViewModel(transaction: tx)
        #expect(vm.transactionType == .income)
    }

    @Test @MainActor func initPreservesTimestamp() async throws {
        let date = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let tx = TransactionModel(timestamp: date, amount: -75, note: "Dinner", category: "Food")
        let vm = EditAddTransactionViewModel(transaction: tx)
        #expect(vm.date == date)
    }

    @Test @MainActor func initPreservesCurrencyCode() async throws {
        let tx = TransactionModel(timestamp: Date(), amount: -75, note: "Dinner", category: "Food", currencyCode: "GBP")
        let vm = EditAddTransactionViewModel(transaction: tx)
        #expect(vm.currencyCode == "GBP")
    }

    @Test @MainActor func initStoresEditingItem() async throws {
        let tx = TransactionModel(timestamp: Date(), amount: -75, note: "Dinner", category: "Food")
        let vm = EditAddTransactionViewModel(transaction: tx)
        #expect(vm.editingItem === tx)
    }

    // MARK: resetForm

    @Test @MainActor func resetFormClearsNameAndAmount() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionName = "Test"
        vm.amount = 100
        vm.resetForm()
        #expect(vm.transactionName == "")
        #expect(vm.amount == 0)
    }

    @Test @MainActor func resetFormClearsCategory() async throws {
        let vm = EditAddTransactionViewModel()
        vm.selectedCategory = expenseCat()
        vm.resetForm()
        #expect(vm.selectedCategory == nil)
    }

    @Test @MainActor func resetFormClearsGoal() async throws {
        let vm = EditAddTransactionViewModel()
        let goal = GoalModel(name: "Savings", targetAmount: 10000, deadline: Date())
        vm.selectedGoal = goal
        vm.resetForm()
        #expect(vm.selectedGoal == nil)
    }

    @Test @MainActor func resetFormResetsTypeToExpense() async throws {
        let vm = EditAddTransactionViewModel()
        vm.transactionType = .income
        vm.resetForm()
        #expect(vm.transactionType == .expense)
    }

    @Test @MainActor func resetFormResetsDateToNow() async throws {
        let vm = EditAddTransactionViewModel()
        vm.date = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let beforeReset = Date()
        vm.resetForm()
        let afterReset = Date()
        #expect(vm.date >= beforeReset && vm.date <= afterReset)
    }

    // MARK: default initialization

    @Test @MainActor func initDefaultCreatesNilEditingItem() async throws {
        let vm = EditAddTransactionViewModel()
        #expect(vm.editingItem == nil)
    }

    @Test @MainActor func initDefaultSetsExpenseType() async throws {
        let vm = EditAddTransactionViewModel()
        #expect(vm.transactionType == .expense)
    }

    @Test @MainActor func initDefaultSetsEmptyName() async throws {
        let vm = EditAddTransactionViewModel()
        #expect(vm.transactionName == "")
    }

    @Test @MainActor func initDefaultSetsZeroAmount() async throws {
        let vm = EditAddTransactionViewModel()
        #expect(vm.amount == 0)
    }

    @Test @MainActor func initDefaultSetsEUR() async throws {
        let vm = EditAddTransactionViewModel()
        #expect(vm.currencyCode == "EUR")
    }

    @Test @MainActor func initDefaultSetsEmptyCategories() async throws {
        let vm = EditAddTransactionViewModel()
        #expect(vm.availableCategories.isEmpty)
    }
}
