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

        let dailyActuals = computeDailyActuals(expenseTransactions, from: startOfMonth, upToDay: daysElapsed)

        return SpendingForecast(
            projectedAmount: projected,
            dailyPace: dailyPace,
            lastThreeMonthAvg: lastThreeMonthAvg,
            daysLeft: daysLeft,
            dailyActuals: dailyActuals
        )
    }

    private func computeDailyActuals(
        _ expenseTransactions: [TransactionModel],
        from startOfMonth: Date,
        upToDay daysElapsed: Int
    ) -> [DailyPoint] {
        let calendar = Calendar.current
        var dailyTotals: [Int: Decimal] = [:]

        for transaction in expenseTransactions {
            guard transaction.timestamp >= startOfMonth else { continue }
            let dayComponent = calendar.dateComponents([.day], from: startOfMonth, to: transaction.timestamp).day ?? 0
            let day = dayComponent + 1
            guard day >= 1 && day <= daysElapsed else { continue }

            let converted = currencyService.convertToBase(transaction.amount, from: transaction.currencyCode)
            dailyTotals[day, default: 0] += converted
        }

        var cumulativeTotal: Decimal = 0
        var points: [DailyPoint] = []

        for day in 1...daysElapsed {
            let dayExpense = abs(dailyTotals[day] ?? 0)
            cumulativeTotal += dayExpense
            points.append(DailyPoint(day: day, cumulative: cumulativeTotal))
        }

        return points
    }

    private func sumExpenses(_ items: [TransactionModel]) -> Decimal {
        abs(items.reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) })
    }
}
