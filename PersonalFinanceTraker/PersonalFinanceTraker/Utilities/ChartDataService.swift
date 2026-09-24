//
//  ChartDataService.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import Foundation

class ChartDataService {

    private let currencyService = CurrencyService()

    init() {}

    func generateChartData(from items: [TransactionSnapshot], for timePeriod: TimePeriod, referenceDate: Date = Date(), payCycleStartDay: Int = 1) -> [ChartDataPoint] {
        switch timePeriod {
        case .week:
            let filteredItems = filterItems(items, for: timePeriod, referenceDate: referenceDate, payCycleStartDay: payCycleStartDay)
            return generateWeeklyData(from: filteredItems, referenceDate: referenceDate)
        case .month:
            let filteredItems = filterItems(items, for: timePeriod, referenceDate: referenceDate, payCycleStartDay: payCycleStartDay)
            return generateMonthlyData(from: filteredItems, referenceDate: referenceDate, payCycleStartDay: payCycleStartDay)
        case .year:
            // ponytail: unfiltered `items`, not run through filterItems — the .year pre-filter's
            // `<= referenceDate` upper bound would empty out the in-progress-month bucket that
            // generateYearlyData used to show (#154); each financial-month window filters itself,
            // and skipping the pre-filter avoids scanning the full transaction list twice.
            return generateYearlyData(from: items, referenceDate: referenceDate, payCycleStartDay: payCycleStartDay)
        }
    }

    func filterItems(_ items: [TransactionSnapshot], for timePeriod: TimePeriod, referenceDate: Date = Date(), payCycleStartDay: Int = 1) -> [TransactionSnapshot] {
        switch timePeriod {
        case .month:
            let start = PayCycleService.financialMonthStart(for: referenceDate, startDay: payCycleStartDay)
            let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
            return items.filter { $0.timestamp >= start && $0.timestamp < end }
        default:
            let calendar = Calendar.current
            let startDate = calendar.date(byAdding: .day, value: -timePeriod.days, to: referenceDate) ?? referenceDate
            return items.filter { item in
                item.timestamp >= startDate && item.timestamp <= referenceDate
            }
        }
    }

    // MARK: - Private Methods

    private func generateWeeklyData(from items: [TransactionSnapshot], referenceDate: Date) -> [ChartDataPoint] {
        let calendar = Calendar.current
        var data: [ChartDataPoint] = []

        for i in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -i, to: referenceDate) ?? referenceDate
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            let dayItems = items.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
            let income = calculateIncome(from: dayItems)
            let expenses = calculateExpenses(from: dayItems)
            let dayName = date.formatted(.dateTime.weekday(.abbreviated))

            data.append(ChartDataPoint(period: dayName, income: income, expenses: expenses, date: dayStart))
        }

        return data.reversed()
    }

    // ponytail: weeks anchored to the financial-month start (not rolling from "today"), so
    // every day in the month lands in exactly one bucket, matching what filterItems(for: .month) kept.
    private func generateMonthlyData(from items: [TransactionSnapshot], referenceDate: Date, payCycleStartDay: Int) -> [ChartDataPoint] {
        let calendar = Calendar.current
        let monthStart = PayCycleService.financialMonthStart(for: referenceDate, startDay: payCycleStartDay, calendar: calendar)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        var data: [ChartDataPoint] = []
        var weekStart = monthStart
        var weekNumber = 1
        while weekStart < monthEnd {
            let weekEnd = min(calendar.date(byAdding: .day, value: 7, to: weekStart) ?? monthEnd, monthEnd)
            let weekItems = items.filter { $0.timestamp >= weekStart && $0.timestamp < weekEnd }
            let income = calculateIncome(from: weekItems)
            let expenses = calculateExpenses(from: weekItems)

            data.append(ChartDataPoint(period: String(localized: "Week \(weekNumber)"), income: income, expenses: expenses, date: weekStart))
            weekStart = weekEnd
            weekNumber += 1
        }

        return data
    }

    // ponytail: 12 *complete* financial months, not the in-progress one — a month-to-date
    // bucket next to 12 full-month ones always reads as a cliff (#154). Ask for 13 and drop the
    // last (current) one instead of a separate "is this the last bucket" branch.
    private func generateYearlyData(from items: [TransactionSnapshot], referenceDate: Date, payCycleStartDay: Int) -> [ChartDataPoint] {
        let calendar = Calendar.current
        let months = PayCycleService.financialMonths(count: 13, before: referenceDate, startDay: payCycleStartDay, calendar: calendar).dropLast()

        return months.map { month in
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: month.start) ?? month.start
            let monthItems = items.filter { $0.timestamp >= month.start && $0.timestamp < monthEnd }
            let income = calculateIncome(from: monthItems)
            let expenses = calculateExpenses(from: monthItems)
            let monthName = month.start.formatted(.dateTime.month(.abbreviated))

            return ChartDataPoint(period: monthName, income: income, expenses: expenses, date: month.start)
        }
    }

    private func calculateIncome(from items: [TransactionSnapshot]) -> Decimal {
        items.filter { $0.amount > 0 }.reduce(0) { total, item in
            total + currencyService.convertToBase(item.amount, from: item.currencyCode)
        }
    }

    private func calculateExpenses(from items: [TransactionSnapshot]) -> Decimal {
        abs(items.filter { $0.amount < 0 }.reduce(0) { total, item in
            total + currencyService.convertToBase(item.amount, from: item.currencyCode)
        })
    }
}

// MARK: - Extensions

extension ChartDataService {
    public func getRecentData(from items: [TransactionSnapshot], count: Int, for timePeriod: TimePeriod) -> [ChartDataPoint] {
        let allData = generateChartData(from: items, for: timePeriod)
        return Array(allData.suffix(count))
    }

    public func getSummaryStats(from items: [TransactionSnapshot], for timePeriod: TimePeriod, payCycleStartDay: Int = 1) -> (income: Decimal, expenses: Decimal, net: Decimal) {
        let filteredItems = filterItems(items, for: timePeriod, payCycleStartDay: payCycleStartDay)
        let income = calculateIncome(from: filteredItems)
        let expenses = calculateExpenses(from: filteredItems)
        return (income: income, expenses: expenses, net: income - expenses)
    }
}
