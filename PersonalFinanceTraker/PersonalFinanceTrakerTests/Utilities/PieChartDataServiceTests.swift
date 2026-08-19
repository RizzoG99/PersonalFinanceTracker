import Testing
import Foundation
import SwiftUI
@testable import PersonalFinanceTraker

struct PieChartDataServiceTests {

    private func expense(_ amount: Decimal, category: String) -> TransactionSnapshot {
        .test(amount: -amount, category: category)
    }

    private func income(_ amount: Decimal, category: String) -> TransactionSnapshot {
        .test(amount: amount, category: category)
    }

    @Test func groupsByCategory() {
        let sut = PieChartDataService()
        let txs = [expense(50, category: "Food"), expense(30, category: "Transport")]
        let result = sut.generatePieChartData(from: txs, for: .expenses, timePeriod: .week)
        let cats = Set(result.map { $0.category })
        #expect(cats == Set(["Food", "Transport"]))
    }

    @Test func sameCategorisSummed() {
        let sut = PieChartDataService()
        let txs = [expense(50, category: "Food"), expense(20, category: "Food")]
        let result = sut.generatePieChartData(from: txs, for: .expenses, timePeriod: .week)
        #expect(result.first { $0.category == "Food" }?.amount == 70)
    }

    @Test func percentagesSumToApproximately100() {
        let sut = PieChartDataService()
        let txs = [expense(60, category: "Food"), expense(40, category: "Transport")]
        let result = sut.generatePieChartData(from: txs, for: .expenses, timePeriod: .week)
        let total = result.map { $0.percentage }.reduce(0, +)
        #expect(abs(total - 100) < 0.01)
    }

    @Test func incomeFilterExcludesExpenses() {
        let sut = PieChartDataService()
        let txs = [expense(50, category: "Food"), income(1000, category: "Salary")]
        let result = sut.generatePieChartData(from: txs, for: .income, timePeriod: .week)
        #expect(result.allSatisfy { $0.category != "Food" })
        #expect(result.contains { $0.category == "Salary" })
    }

    @Test func expensesFilterExcludesIncome() {
        let sut = PieChartDataService()
        let txs = [expense(50, category: "Food"), income(1000, category: "Salary")]
        let result = sut.generatePieChartData(from: txs, for: .expenses, timePeriod: .week)
        #expect(result.allSatisfy { $0.category != "Salary" })
    }

    @Test func emptyTransactionsProducesEmptyResult() {
        #expect(PieChartDataService().generatePieChartData(from: [], for: .expenses, timePeriod: .week).isEmpty)
    }

    @Test func getSummaryStatsReturnsCorrectTotalsAndCount() {
        let sut = PieChartDataService()
        let txs = [expense(60, category: "Food"), expense(40, category: "Transport")]
        let stats = sut.getSummaryStats(from: txs, for: .expenses, timePeriod: .week)
        #expect(stats.totalAmount == 100)
        #expect(stats.categoryCount == 2)
    }

    @Test func getTopCategoriesRespectsLimit() {
        let sut = PieChartDataService()
        let txs = (1...10).map { i in expense(Decimal(i * 10), category: "Cat\(i)") }
        let top3 = sut.getTopCategories(from: txs, for: .expenses, timePeriod: .week, limit: 3)
        #expect(top3.count == 3)
    }

    @Test func emptyCategoryFallsBackToOther() {
        let sut = PieChartDataService()
        let tx = TransactionSnapshot.test(amount: -30, category: "")
        let result = sut.generatePieChartData(from: [tx], for: .expenses, timePeriod: .week)
        #expect(result.first?.category == "Other")
    }

    @Test func sliceColourComesFromTheCategorysOwnToken() {
        let sut = PieChartDataService()
        let food = CategorySnapshot.test(name: "Food", colorToken: "categoryPink")
        let result = sut.generatePieChartData(
            from: [expense(50, category: "Food")],
            for: .expenses,
            timePeriod: .week,
            categories: [food]
        )
        #expect(result.first?.color == Color(categoryToken: "categoryPink"))
    }

    /// Regression guard. Colours used to be assigned by index after sorting by amount,
    /// so a category's slice changed colour whenever its spending rank changed.
    @Test func sliceColourIsStableWhenSpendingRankChanges() {
        let sut = PieChartDataService()
        let cats = [
            CategorySnapshot.test(name: "Food", colorToken: "categoryTeal"),
            CategorySnapshot.test(name: "Transport", colorToken: "categoryAmber")
        ]

        func foodColour(food: Decimal, transport: Decimal) -> Color? {
            sut.generatePieChartData(
                from: [expense(food, category: "Food"), expense(transport, category: "Transport")],
                for: .expenses,
                timePeriod: .week,
                categories: cats
            ).first { $0.category == "Food" }?.color
        }

        let whenRankedFirst = foodColour(food: 90, transport: 10)
        let whenRankedLast = foodColour(food: 10, transport: 90)

        #expect(whenRankedFirst == whenRankedLast)
        #expect(whenRankedFirst == Color(categoryToken: "categoryTeal"))
    }

    /// Regression guard: `.month` used to always resolve the *current* financial month and
    /// silently ignore `referenceDate`, so asking for "last month" returned this month's data —
    /// which is why Category Trends always showed "0%" (current vs. current diffs to nothing).
    @Test func monthFilterUsesReferenceDateNotToday() {
        let calendar = Calendar.current
        let now = Date.now
        let lastMonthRef = calendar.date(byAdding: .month, value: -1, to: now)!

        let thisMonthTx = TransactionSnapshot.test(timestamp: now, amount: -50, category: "Food")
        let lastMonthTx = TransactionSnapshot.test(timestamp: lastMonthRef, amount: -80, category: "Food")

        let sut = PieChartDataService()
        let currentResult = sut.generatePieChartData(
            from: [thisMonthTx, lastMonthTx], for: .expenses, timePeriod: .month
        )
        let lastResult = sut.generatePieChartData(
            from: [thisMonthTx, lastMonthTx], for: .expenses, timePeriod: .month, referenceDate: lastMonthRef
        )

        #expect(currentResult.first?.amount == 50)
        #expect(lastResult.first?.amount == 80)
    }

    @Test func unknownCategoryFallsBackToTheNameDerivedToken() {
        let sut = PieChartDataService()
        let result = sut.generatePieChartData(
            from: [expense(50, category: "Groceries")],
            for: .expenses,
            timePeriod: .week,
            categories: []
        )
        #expect(result.first?.color == Color(categoryToken: CategoryConstants.colorToken(forName: "Groceries")))
    }
}
