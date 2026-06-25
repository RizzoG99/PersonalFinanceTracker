import Testing
import Foundation
@testable import PersonalFinanceTraker

struct PieChartDataServiceTests {

    private func expense(_ amount: Decimal, category: String) -> TransactionModel {
        TransactionModel(timestamp: Date(), amount: -amount, note: "", category: category)
    }

    private func income(_ amount: Decimal, category: String) -> TransactionModel {
        TransactionModel(timestamp: Date(), amount: amount, note: "", category: category)
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
        let tx = TransactionModel(timestamp: Date(), amount: -30, note: "", category: "")
        let result = sut.generatePieChartData(from: [tx], for: .expenses, timePeriod: .week)
        #expect(result.first?.category == "Other")
    }
}
