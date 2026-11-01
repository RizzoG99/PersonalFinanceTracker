import Testing
@testable import PersonalFinanceTraker
import Foundation

@Suite
struct BudgetProgressServiceTests {

    @Test func includesCategoryWithBudgetSet() {
        let category = CategorySnapshot.test(name: "Groceries", monthlyBudget: 300)
        let (cycleStart, _) = PayCycleService.currentFinancialMonth(startDay: 1)
        let tx = TransactionSnapshot.test(timestamp: cycleStart, amount: -50, category: "Groceries")

        let result = BudgetProgressService.computeProgress(
            categories: [category], transactions: [tx], payCycleStartDay: 1
        )

        #expect(result.count == 1)
        #expect(result.first?.categoryName == "Groceries")
        #expect(result.first?.budget == 300)
        #expect(result.first?.spent == 50)
    }

    @Test func excludesCategoryWithoutBudget() {
        let category = CategorySnapshot.test(name: "Fun", monthlyBudget: nil)
        let result = BudgetProgressService.computeProgress(
            categories: [category], transactions: [], payCycleStartDay: 1
        )
        #expect(result.isEmpty)
    }

    @Test func excludesCategoryWithZeroBudget() {
        let category = CategorySnapshot.test(name: "Fun", monthlyBudget: 0)
        let result = BudgetProgressService.computeProgress(
            categories: [category], transactions: [], payCycleStartDay: 1
        )
        #expect(result.isEmpty)
    }

    @Test func excludesIncomeCategories() {
        let category = CategorySnapshot.test(name: "Salary", type: .income, monthlyBudget: 1000)
        let result = BudgetProgressService.computeProgress(
            categories: [category], transactions: [], payCycleStartDay: 1
        )
        #expect(result.isEmpty)
    }

    @Test func excludesTransactionOutsideCurrentCycle() {
        let category = CategorySnapshot.test(name: "Groceries", monthlyBudget: 300)
        let (cycleStart, _) = PayCycleService.currentFinancialMonth(startDay: 1)
        let before = Calendar.current.date(byAdding: .day, value: -1, to: cycleStart)!
        let tx = TransactionSnapshot.test(timestamp: before, amount: -50, category: "Groceries")

        let result = BudgetProgressService.computeProgress(
            categories: [category], transactions: [tx], payCycleStartDay: 1
        )
        #expect(result.first?.spent == 0)
    }

    /// #342: spending on the cycle's last day used to fall after the midnight `end`.
    @Test func countsSpendingOnTheCycleLastDay() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 18))!
        let lastDayAfternoon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 17))!
        let category = CategorySnapshot.test(name: "Fun", monthlyBudget: 50)
        let tx = TransactionSnapshot.test(timestamp: lastDayAfternoon, amount: -45, category: "Fun")

        let result = BudgetProgressService.computeProgress(
            categories: [category], transactions: [tx], payCycleStartDay: 1, now: now, calendar: calendar
        )

        #expect(result.first?.spent == 45)
        #expect(BudgetProgressService.nearLimit(result).count == 1)
    }

    @Test func excludesSpendingAtTheNextCycleStart() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 18))!
        let nextCycleStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let category = CategorySnapshot.test(name: "Fun", monthlyBudget: 50)
        let tx = TransactionSnapshot.test(timestamp: nextCycleStart, amount: -45, category: "Fun")

        let result = BudgetProgressService.computeProgress(
            categories: [category], transactions: [tx], payCycleStartDay: 1, now: now, calendar: calendar
        )

        #expect(result.first?.spent == 0)
    }

    @Test func excludesIncomeTransactionsFromSpent() {
        let category = CategorySnapshot.test(name: "Groceries", monthlyBudget: 300)
        let (cycleStart, _) = PayCycleService.currentFinancialMonth(startDay: 1)
        let tx = TransactionSnapshot.test(timestamp: cycleStart, amount: 50, category: "Groceries")

        let result = BudgetProgressService.computeProgress(
            categories: [category], transactions: [tx], payCycleStartDay: 1
        )
        #expect(result.first?.spent == 0)
    }

    @Test func percentAndOverBudgetComputedCorrectly() {
        let progress = BudgetProgress(
            id: CategorySnapshot.test(name: "Groceries", monthlyBudget: 200).persistentId,
            categoryName: "Groceries", systemImage: "cart", colorToken: "categoryGreen",
            budget: 200, spent: 180
        )
        #expect(progress.percent == 0.9)
        #expect(progress.isOverBudget == false)

        let over = BudgetProgress(
            id: progress.id, categoryName: "Groceries", systemImage: "cart", colorToken: "categoryGreen",
            budget: 200, spent: 250
        )
        #expect(over.isOverBudget == true)
    }

    @Test func nearLimitFiltersAndSortsDescending() {
        let low = BudgetProgress(id: CategorySnapshot.test(name: "A", monthlyBudget: 100).persistentId, categoryName: "A", systemImage: "cart", colorToken: "categoryGreen", budget: 100, spent: 10)
        let high = BudgetProgress(id: CategorySnapshot.test(name: "B", monthlyBudget: 100).persistentId, categoryName: "B", systemImage: "cart", colorToken: "categoryGreen", budget: 100, spent: 95)
        let mid = BudgetProgress(id: CategorySnapshot.test(name: "C", monthlyBudget: 100).persistentId, categoryName: "C", systemImage: "cart", colorToken: "categoryGreen", budget: 100, spent: 85)

        let result = BudgetProgressService.nearLimit([low, high, mid], threshold: 0.8)

        #expect(result.map(\.categoryName) == ["B", "C"])
    }
}
