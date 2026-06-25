import Testing
import Foundation
@testable import PersonalFinanceTraker

// MARK: - ChartDataPoint

struct ChartDataPointTests {

    @Test func netAmountIsIncomMinusExpenses() {
        #expect(ChartDataPoint(period: "Jan", income: 1000, expenses: 600).netAmount == 400)
    }

    @Test func isProfit() {
        let pt = ChartDataPoint(period: "Jan", income: 1000, expenses: 600)
        #expect(pt.isProfit == true)
        #expect(pt.isLoss == false)
        #expect(pt.isBreakEven == false)
    }

    @Test func isLoss() {
        let pt = ChartDataPoint(period: "Jan", income: 200, expenses: 600)
        #expect(pt.isLoss == true)
        #expect(pt.isProfit == false)
        #expect(pt.isBreakEven == false)
    }

    @Test func isBreakEven() {
        let pt = ChartDataPoint(period: "Jan", income: 500, expenses: 500)
        #expect(pt.isBreakEven == true)
        #expect(pt.isProfit == false)
        #expect(pt.isLoss == false)
    }

    @Test func hasActivityWhenIncomePresent() {
        #expect(ChartDataPoint(period: "Jan", income: 100, expenses: 0).hasActivity == true)
    }

    @Test func hasActivityWhenExpensesPresent() {
        #expect(ChartDataPoint(period: "Jan", income: 0, expenses: 50).hasActivity == true)
    }

    @Test func noActivityWhenBothZero() {
        #expect(ChartDataPoint(period: "Jan", income: 0, expenses: 0).hasActivity == false)
    }
}

// MARK: - CreditCardModel

struct CreditCardModelTests {

    @Test func utilizationRateIsBalanceDividedByLimit() {
        let card = CreditCardModel(name: "Visa", lastFour: "1234", balance: 50, limit: 200)
        #expect(abs(card.utilizationRate - 0.25) < 0.001)
    }

    @Test func utilizationRateCapsAtOne() {
        let card = CreditCardModel(name: "Visa", lastFour: "1234", balance: 500, limit: 200)
        #expect(card.utilizationRate == 1.0)
    }

    @Test func utilizationRateIsZeroWhenLimitIsZero() {
        let card = CreditCardModel(name: "Visa", lastFour: "1234", balance: 0, limit: 0)
        #expect(card.utilizationRate == 0)
    }

    @Test func availableIsLimitMinusBalance() {
        let card = CreditCardModel(name: "Visa", lastFour: "1234", balance: 300, limit: 1000)
        #expect(card.available == 700)
    }

    @Test func availableIsZeroWhenBalanceExceedsLimit() {
        let card = CreditCardModel(name: "Visa", lastFour: "1234", balance: 1500, limit: 1000)
        #expect(card.available == 0)
    }
}
