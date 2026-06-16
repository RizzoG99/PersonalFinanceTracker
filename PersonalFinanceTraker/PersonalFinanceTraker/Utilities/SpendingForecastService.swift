//
//  SpendingForecastService.swift
//  PersonalFinanceTraker
//

import Foundation

struct SpendingForecastService {
    let currencyService: CurrencyService

    func compute(expenseTransactions: [TransactionModel]) -> SpendingForecast {
        let calendar = Calendar.current
        let now = Date.now
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let daysElapsed = max(1, calendar.dateComponents([.day], from: startOfMonth, to: now).day ?? 1)
        let daysLeft = max(0, daysInMonth - daysElapsed)

        let currentMonthExpenses = sumExpenses(expenseTransactions.filter { $0.timestamp >= startOfMonth })
        let dailyPace = currentMonthExpenses / Decimal(daysElapsed)
        let projected = dailyPace * Decimal(daysInMonth)

        let threeMonthTotal = (1...3).reduce(Decimal(0)) { total, offset in
            let start = calendar.date(byAdding: .month, value: -offset, to: startOfMonth) ?? startOfMonth
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return total + sumExpenses(expenseTransactions.filter { $0.timestamp >= start && $0.timestamp < end })
        }
        let lastThreeMonthAvg = threeMonthTotal / 3

        return SpendingForecast(
            projectedAmount: projected,
            dailyPace: dailyPace,
            lastThreeMonthAvg: lastThreeMonthAvg,
            daysLeft: daysLeft
        )
    }

    private func sumExpenses(_ items: [TransactionModel]) -> Decimal {
        abs(items.reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) })
    }
}
