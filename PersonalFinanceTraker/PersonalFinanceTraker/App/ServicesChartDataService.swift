//
//  ChartDataService.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import Foundation

/// Service class for generating chart data from financial transactions
///
/// This service provides methods to filter and aggregate financial data
/// for different time periods, creating chart-ready data points.
///
/// ## Usage
/// ```swift
/// let service = ChartDataService()
/// let chartData = service.generateChartData(
///     from: transactions,
///     for: .month
/// )
/// ```
///
/// ## Features
/// - Supports week, month, and year aggregations
/// - Automatic date grouping and filtering
/// - Proper handling of income vs expenses
/// - Configurable time periods
public class ChartDataService {
    
    /// Creates a new chart data service
    public init() {}
    
    /// Generates chart data points from a collection of financial items
    /// - Parameters:
    ///   - items: Array of financial items to process
    ///   - timePeriod: The time period for data aggregation
    ///   - referenceDate: The reference date for calculations (defaults to current date)
    /// - Returns: Array of chart data points ready for display
    public func generateChartData(from items: [TransactionModel], for timePeriod: TimePeriod, referenceDate: Date = Date()) -> [ChartDataPoint] {
        let filteredItems = filterItems(items, for: timePeriod, referenceDate: referenceDate)
        
        switch timePeriod {
        case .week:
            return generateWeeklyData(from: filteredItems, referenceDate: referenceDate)
        case .month:
            return generateMonthlyData(from: filteredItems, referenceDate: referenceDate)
        case .year:
            return generateYearlyData(from: filteredItems, referenceDate: referenceDate)
        }
    }
    
    /// Filters items based on the specified time period
    /// - Parameters:
    ///   - items: Array of items to filter
    ///   - timePeriod: Time period for filtering
    ///   - referenceDate: Reference date for calculations
    /// - Returns: Filtered array of items within the time period
    public func filterItems(_ items: [TransactionModel], for timePeriod: TimePeriod, referenceDate: Date = Date()) -> [TransactionModel] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -timePeriod.days, to: referenceDate) ?? referenceDate
        
        return items.filter { item in
            item.timestamp >= startDate && item.timestamp <= referenceDate
        }
    }
    
    // MARK: - Private Methods
    
    /// Generates daily data for the week view
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
            
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            let dayName = formatter.string(from: date)
            
            data.append(ChartDataPoint(period: dayName, income: income, expenses: expenses))
        }
        
        return data.reversed()
    }
    
    /// Generates weekly data for the month view
    private func generateMonthlyData(from items: [TransactionModel], referenceDate: Date) -> [ChartDataPoint] {
        let calendar = Calendar.current
        var data: [ChartDataPoint] = []
        
        for i in 0..<4 {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -i, to: referenceDate) ?? referenceDate
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
            
            let weekItems = items.filter { $0.timestamp >= weekStart && $0.timestamp < weekEnd }
            let income = calculateIncome(from: weekItems)
            let expenses = calculateExpenses(from: weekItems)
            
            data.append(ChartDataPoint(period: "Week \(4-i)", income: income, expenses: expenses))
        }
        
        return data.reversed()
    }
    
    /// Generates monthly data for the year view
    private func generateYearlyData(from items: [TransactionModel], referenceDate: Date) -> [ChartDataPoint] {
        let calendar = Calendar.current
        var data: [ChartDataPoint] = []
        
        for i in 0..<12 {
            let monthStart = calendar.date(byAdding: .month, value: -i, to: referenceDate) ?? referenceDate
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            
            let monthItems = items.filter { $0.timestamp >= monthStart && $0.timestamp < monthEnd }
            let income = calculateIncome(from: monthItems)
            let expenses = calculateExpenses(from: monthItems)
            
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            let monthName = formatter.string(from: monthStart)
            
            data.append(ChartDataPoint(period: monthName, income: income, expenses: expenses))
        }
        
        return data.reversed()
    }
    
    /// Calculates total income from items
    /// - Parameter items: Array of items to calculate from
    /// - Returns: Total income amount
    private func calculateIncome(from items: [TransactionModel]) -> Decimal {
        return items.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
    }
    
    /// Calculates total expenses from items (returned as positive value)
    /// - Parameter items: Array of items to calculate from
    /// - Returns: Total expenses as positive amount
    private func calculateExpenses(from items: [TransactionModel]) -> Decimal {
        return abs(items.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount })
    }
}

// MARK: - Extensions

extension ChartDataService {
    /// Convenience method to get the most recent data points
    /// - Parameters:
    ///   - items: Array of items to process
    ///   - count: Number of recent periods to include
    ///   - timePeriod: Time period for aggregation
    /// - Returns: Array of the most recent chart data points
    public func getRecentData(from items: [TransactionModel], count: Int, for timePeriod: TimePeriod) -> [ChartDataPoint] {
        let allData = generateChartData(from: items, for: timePeriod)
        return Array(allData.suffix(count))
    }
    
    /// Gets summary statistics for a time period
    /// - Parameters:
    ///   - items: Array of items to analyze
    ///   - timePeriod: Time period for analysis
    /// - Returns: A tuple containing total income, expenses, and net amount
    public func getSummaryStats(from items: [TransactionModel], for timePeriod: TimePeriod) -> (income: Decimal, expenses: Decimal, net: Decimal) {
        let filteredItems = filterItems(items, for: timePeriod)
        let income = calculateIncome(from: filteredItems)
        let expenses = calculateExpenses(from: filteredItems)
        let net = income - expenses
        
        return (income: income, expenses: expenses, net: net)
    }
}
