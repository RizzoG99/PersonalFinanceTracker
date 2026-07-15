//
//  SpendingForecastService.swift
//  PersonalFinanceTraker
//

import Foundation

struct SpendingForecastService {
    let currencyService: CurrencyService

    func compute(
        expenseTransactions: [TransactionSnapshot],
        cache: ForecastCacheState?,
        now: Date = .now
    ) -> (forecast: SpendingForecast, updatedCache: ForecastCacheState) {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let daysElapsed = max(1, (calendar.dateComponents([.day], from: startOfMonth, to: now).day ?? 0) + 1)
        let daysLeft = max(0, daysInMonth - daysElapsed)
        let currentMonthKey = monthKey(for: now)

        // Sliding window setup
        let cacheIsValid = cache != nil
            && cache!.monthKey == currentMonthKey
            && cache!.computedUpToDay < daysElapsed
        let cacheIsUpToDate = cache != nil
            && cache!.monthKey == currentMonthKey
            && cache!.computedUpToDay >= daysElapsed

        var days: [Int]
        var amounts: [Double]
        let startDay: Int
        var runningTotal: Double

        if cacheIsUpToDate {
            // Nothing new — reuse as-is
            days = cache!.days
            amounts = cache!.amounts
            startDay = daysElapsed + 1  // loop won't execute
            runningTotal = amounts.last ?? 0
        } else if cacheIsValid {
            days = cache!.days
            amounts = cache!.amounts
            startDay = cache!.computedUpToDay + 1
            runningTotal = amounts.last ?? 0
        } else {
            // Full recompute (nil cache or month boundary)
            days = []
            amounts = []
            startDay = 1
            runningTotal = 0
        }

        // Compute new days (startDay..daysElapsed)
        if startDay <= daysElapsed {
            for day in startDay...daysElapsed {
                let dayStart = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) ?? startOfMonth
                let dayEnd   = calendar.date(byAdding: .day, value: day,     to: startOfMonth) ?? startOfMonth
                let dayTotal = sumExpenses(
                    expenseTransactions.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
                )
                runningTotal += NSDecimalNumber(decimal: dayTotal).doubleValue
                days.append(day)
                amounts.append(runningTotal)
            }
        }

        // Build DailyPoint array for chart
        let dailyActuals: [DailyPoint] = zip(days, amounts).map { day, amount in
            DailyPoint(day: day, cumulative: Decimal(string: String(amount)) ?? Decimal(amount))
        }

        // Aggregate forecast metrics (unchanged logic)
        let currentMonthExpenses = sumExpenses(expenseTransactions.filter { $0.timestamp >= startOfMonth })
        let dailyPace = currentMonthExpenses / Decimal(daysElapsed)
        let projected = dailyPace * Decimal(daysInMonth)

        let threeMonthTotal = (1...3).reduce(Decimal(0)) { total, offset in
            let start = calendar.date(byAdding: .month, value: -offset, to: startOfMonth) ?? startOfMonth
            let end   = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return total + sumExpenses(expenseTransactions.filter { $0.timestamp >= start && $0.timestamp < end })
        }
        let lastThreeMonthAvg = threeMonthTotal / 3

        let forecast = SpendingForecast(
            projectedAmount: projected,
            dailyPace: dailyPace,
            lastThreeMonthAvg: lastThreeMonthAvg,
            daysLeft: daysLeft,
            dailyActuals: dailyActuals
        )
        let updatedCache = ForecastCacheState(
            monthKey: currentMonthKey,
            computedUpToDay: daysElapsed,
            days: days,
            amounts: amounts
        )
        return (forecast, updatedCache)
    }

    // MARK: - Private

    private func monthKey(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(comps.year ?? 0)-\(String(format: "%02d", comps.month ?? 0))"
    }

    private func sumExpenses(_ items: [TransactionSnapshot]) -> Decimal {
        abs(items.reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) })
    }
}
