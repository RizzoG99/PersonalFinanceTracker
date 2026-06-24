import Testing
import Foundation
@testable import PersonalFinanceTraker

struct StatisticalAverageServiceTests {

    private func income(_ amount: Decimal, monthsAgo: Int = 0) -> TransactionModel {
        let date = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: .now) ?? .now
        return TransactionModel(timestamp: date, amount: amount, note: "", category: "Salary")
    }

    private func expense(_ amount: Decimal, monthsAgo: Int = 0) -> TransactionModel {
        let date = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: .now) ?? .now
        return TransactionModel(timestamp: date, amount: -amount, note: "", category: "Food")
    }

    @Test func averageIncomeAcrossSixMonths() {
        let sut = StatisticalAverageService(currencyService: CurrencyService())
        let txs = (0..<6).map { income(600, monthsAgo: $0) }
        let result = sut.calculate(transactions: txs, expenseTransactions: [])
        // 3600 total / 6 = 600
        #expect(result.income == 600)
    }

    @Test func averageExpensesAcrossSixMonths() {
        let sut = StatisticalAverageService(currencyService: CurrencyService())
        let txs = (0..<6).map { expense(300, monthsAgo: $0) }
        let result = sut.calculate(transactions: [], expenseTransactions: txs)
        // 1800 total / 6 = 300
        #expect(result.expenses == 300)
    }

    @Test func savingsIsIncomMinusExpenses() {
        let sut = StatisticalAverageService(currencyService: CurrencyService())
        let inc = (0..<6).map { income(1000, monthsAgo: $0) }
        let exp = (0..<6).map { expense(400, monthsAgo: $0) }
        let result = sut.calculate(transactions: inc, expenseTransactions: exp)
        #expect(result.savings == 600)
    }

    @Test func transactionsOlderThanSixMonthsExcluded() {
        let sut = StatisticalAverageService(currencyService: CurrencyService())
        let old = income(10000, monthsAgo: 7)   // outside 6-month window
        let recent = income(600, monthsAgo: 1)
        let result = sut.calculate(transactions: [old, recent], expenseTransactions: [])
        // Only recent counts: 600 / 6 = 100
        #expect(result.income == 100)
    }

    @Test func zeroTransactionsReturnsAllZero() {
        let sut = StatisticalAverageService(currencyService: CurrencyService())
        let result = sut.calculate(transactions: [], expenseTransactions: [])
        #expect(result.income == 0)
        #expect(result.expenses == 0)
        #expect(result.savings == 0)
    }
}
