//
//  StatisticalAverageService.swift
//  PersonalFinanceTraker
//

import Foundation

struct StatisticalAverageService {
    let currencyService: CurrencyService

    func calculate(
        transactions: [TransactionSnapshot],
        expenseTransactions: [TransactionSnapshot]
    ) -> (income: Decimal, expenses: Decimal, savings: Decimal) {
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now
        let recent = transactions.filter { $0.timestamp >= sixMonthsAgo }
        let recentExpenses = expenseTransactions.filter { $0.timestamp >= sixMonthsAgo }

        let totalIncome = recent.filter { $0.amount > 0 }.reduce(Decimal(0)) {
            $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode)
        }
        let totalExpenses = sumExpenses(recentExpenses)

        let income = totalIncome / 6
        let expenses = totalExpenses / 6
        return (income: income, expenses: expenses, savings: income - expenses)
    }

    private func sumExpenses(_ items: [TransactionSnapshot]) -> Decimal {
        abs(items.reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) })
    }
}
