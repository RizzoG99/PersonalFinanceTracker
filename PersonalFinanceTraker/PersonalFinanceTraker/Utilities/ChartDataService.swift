//
//  ChartDataService.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import Foundation

public class ChartDataService {

    private let currencyService = CurrencyService()

    public init() {}

    public func generateChartData(from items: [TransactionModel], for timePeriod: TimePeriod, referenceDate: Date = Date(), payCycleStartDay: Int = 1) -> [ChartDataPoint] {
        let filteredItems = filterItems(items, for: timePeriod, referenceDate: referenceDate, payCycleStartDay: payCycleStartDay)

        switch timePeriod {
        case .week:
            return generateWeeklyData(from: filteredItems, referenceDate: referenceDate)
        case .month:
            return generateMonthlyData(from: filteredItems, referenceDate: referenceDate)
        case .year:
            return generateYearlyData(from: filteredItems, referenceDate: referenceDate)
        }
    }

    public func filterItems(_ items: [TransactionModel], for timePeriod: TimePeriod, referenceDate: Date = Date(), payCycleStartDay: Int = 1) -> [TransactionModel] {
        switch timePeriod {
        case .month:
            let (start, end) = PayCycleService.currentFinancialMonth(startDay: payCycleStartDay)
            return items.filter { $0.timestamp >= start && $0.timestamp <= end }
        default:
            let calendar = Calendar.current
            let startDate = calendar.date(byAdding: .day, value: -timePeriod.days, to: referenceDate) ?? referenceDate
            return items.filter { item in
                item.timestamp >= startDate && item.timestamp <= referenceDate
            }
        }
    }

    // MARK: - Private Methods

    private func generateWeeklyData(from items: [TransactionModel], referenceDate: Date) -> [ChartDataPoint] {
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

    private func generateMonthlyData(from items: [TransactionModel], referenceDate: Date) -> [ChartDataPoint] {
        let calendar = Calendar.current
        var data: [ChartDataPoint] = []

        for i in 0..<4 {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -i, to: referenceDate) ?? referenceDate
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart

            let weekItems = items.filter { $0.timestamp >= weekStart && $0.timestamp < weekEnd }
            let income = calculateIncome(from: weekItems)
            let expenses = calculateExpenses(from: weekItems)

            data.append(ChartDataPoint(period: "Week \(4-i)", income: income, expenses: expenses, date: weekStart))
        }

        return data.reversed()
    }

    private func generateYearlyData(from items: [TransactionModel], referenceDate: Date) -> [ChartDataPoint] {
        let calendar = Calendar.current
        var data: [ChartDataPoint] = []

        for i in 0..<12 {
            let monthStart = calendar.date(byAdding: .month, value: -i, to: referenceDate) ?? referenceDate
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

            let monthItems = items.filter { $0.timestamp >= monthStart && $0.timestamp < monthEnd }
            let income = calculateIncome(from: monthItems)
            let expenses = calculateExpenses(from: monthItems)
            let monthName = monthStart.formatted(.dateTime.month(.abbreviated))

            data.append(ChartDataPoint(period: monthName, income: income, expenses: expenses, date: monthStart))
        }

        return data.reversed()
    }

    private func calculateIncome(from items: [TransactionModel]) -> Decimal {
        items.filter { $0.amount > 0 }.reduce(0) { total, item in
            total + currencyService.convertToBase(item.amount, from: item.currencyCode)
        }
    }

    private func calculateExpenses(from items: [TransactionModel]) -> Decimal {
        abs(items.filter { $0.amount < 0 }.reduce(0) { total, item in
            total + currencyService.convertToBase(item.amount, from: item.currencyCode)
        })
    }
}

// MARK: - Extensions

extension ChartDataService {
    public func getRecentData(from items: [TransactionModel], count: Int, for timePeriod: TimePeriod) -> [ChartDataPoint] {
        let allData = generateChartData(from: items, for: timePeriod)
        return Array(allData.suffix(count))
    }

    public func getSummaryStats(from items: [TransactionModel], for timePeriod: TimePeriod, payCycleStartDay: Int = 1) -> (income: Decimal, expenses: Decimal, net: Decimal) {
        let filteredItems = filterItems(items, for: timePeriod, payCycleStartDay: payCycleStartDay)
        let income = calculateIncome(from: filteredItems)
        let expenses = calculateExpenses(from: filteredItems)
        return (income: income, expenses: expenses, net: income - expenses)
    }
}
