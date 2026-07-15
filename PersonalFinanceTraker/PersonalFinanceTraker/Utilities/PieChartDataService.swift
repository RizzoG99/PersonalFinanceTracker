//
//  PieChartDataService.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import Foundation
import SwiftUI

/// Service class for generating pie chart data from financial transactions grouped by categories
///
/// This service provides methods to filter and aggregate financial data
/// by categories, creating pie chart-ready data points.
///
/// ## Usage
/// ```swift
/// let service = PieChartDataService()
/// let pieData = service.generatePieChartData(
///     from: transactions,
///     for: .expenses,
///     timePeriod: .month
/// )
/// ```
///
/// ## Features
/// - Groups transactions by category
/// - Calculates percentages automatically
/// - Assigns colors to categories
/// - Supports filtering by time period
/// - Separate handling for income vs expenses
public class PieChartDataService {
    
    private let currencyService = CurrencyService()
    
    /// Predefined colors for different categories
    private let categoryColors: [Color] = [
        .blue, .green, .orange, .red, .purple,
        .pink, .yellow, .indigo, .mint, .cyan,
        .teal, .brown, .gray
    ]
    
    /// Creates a new pie chart data service
    public init() {}
    
    /// Generates pie chart data points from a collection of financial items
    /// - Parameters:
    ///   - items: Array of financial items to process
    ///   - dataType: Whether to show expenses or income
    ///   - timePeriod: The time period for data filtering
    ///   - referenceDate: The reference date for calculations (defaults to current date)
    ///   - payCycleStartDay: The start day of the financial month (1-28, defaults to 1)
    /// - Returns: Array of pie chart data points ready for display
    func generatePieChartData(
        from items: [TransactionSnapshot],
        for dataType: PieChartDataType,
        timePeriod: TimePeriod,
        referenceDate: Date = Date(),
        payCycleStartDay: Int = 1,
        categories: [CategorySnapshot] = []
    ) -> [PieChartDataPoint] {

        // Filter items by time period and transaction type
        let filteredItems = filterItems(items, for: timePeriod, referenceDate: referenceDate, payCycleStartDay: payCycleStartDay)
        let typeFilteredItems = filterByDataType(filteredItems, dataType: dataType)

        // Group by category and calculate totals
        let categoryGroupedData = groupByCategory(typeFilteredItems)
        let budgetsByName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0.monthlyBudget) })

        // Calculate total amount for percentage calculations
        let totalAmount = categoryGroupedData.values.reduce(0, +)

        // Generate pie chart data points
        var pieChartData: [PieChartDataPoint] = []

        for (index, (categoryName, total)) in categoryGroupedData.sorted(by: { $0.value > $1.value }).enumerated() {
            let percentage = totalAmount > 0 ? Double(truncating: (total / totalAmount * 100) as NSDecimalNumber) : 0
            let color = categoryColors[index % categoryColors.count]

            pieChartData.append(PieChartDataPoint(
                category: categoryName,
                amount: total,
                color: color,
                percentage: percentage,
                budget: budgetsByName[categoryName] ?? nil
            ))
        }

        return pieChartData
    }
    
    /// Gets summary statistics for pie chart data
    /// - Parameters:
    ///   - items: Array of items to analyze
    ///   - dataType: Whether to analyze expenses or income
    ///   - timePeriod: Time period for analysis
    ///   - referenceDate: Reference date for calculations
    ///   - payCycleStartDay: The start day of the financial month (1-28, defaults to 1)
    /// - Returns: A tuple containing total amount and number of categories
    func getSummaryStats(
        from items: [TransactionSnapshot],
        for dataType: PieChartDataType,
        timePeriod: TimePeriod,
        referenceDate: Date = Date(),
        payCycleStartDay: Int = 1
    ) -> (totalAmount: Decimal, categoryCount: Int) {

        let filteredItems = filterItems(items, for: timePeriod, referenceDate: referenceDate, payCycleStartDay: payCycleStartDay)
        let typeFilteredItems = filterByDataType(filteredItems, dataType: dataType)
        let categoryTotals = groupByCategory(typeFilteredItems)

        let totalAmount = categoryTotals.values.reduce(0, +)

        return (totalAmount: totalAmount, categoryCount: categoryTotals.count)
    }
    
    // MARK: - Private Methods
    
    /// Filters items based on the specified time period
    /// - Parameters:
    ///   - items: Array of items to filter
    ///   - timePeriod: Time period for filtering
    ///   - referenceDate: Reference date for calculations
    ///   - payCycleStartDay: The start day of the financial month (1-28, defaults to 1)
    /// - Returns: Filtered array of items within the time period
    private func filterItems(_ items: [TransactionSnapshot], for timePeriod: TimePeriod, referenceDate: Date, payCycleStartDay: Int = 1) -> [TransactionSnapshot] {
        switch timePeriod {
        case .month:
            let (start, end) = PayCycleService.currentFinancialMonth(startDay: payCycleStartDay)
            return items.filter { $0.timestamp >= start && $0.timestamp <= end }
        default:
            let calendar = Calendar.current
            let startDate = calendar.date(byAdding: .day, value: -timePeriod.days, to: referenceDate) ?? referenceDate
            return items.filter { $0.timestamp >= startDate && $0.timestamp <= referenceDate }
        }
    }
    
    /// Filters items by data type (expenses or income)
    /// - Parameters:
    ///   - items: Array of items to filter
    ///   - dataType: Type of data to include
    /// - Returns: Filtered array of items
    private func filterByDataType(_ items: [TransactionSnapshot], dataType: PieChartDataType) -> [TransactionSnapshot] {
        switch dataType {
        case .expenses:
            return items.filter { $0.amount < 0 }
        case .income:
            return items.filter { $0.amount > 0 }
        }
    }
    
    /// Groups items by category and calculates totals
    /// - Parameter items: Array of items to group
    /// - Returns: Dictionary with category names as keys and total amounts as values
    private func groupByCategory(_ items: [TransactionSnapshot]) -> [String: Decimal] {
        var categoryData: [String: Decimal] = [:]

        for item in items {
            let categoryName = item.category.isEmpty ? "Other" : item.category
            let amount = abs(currencyService.convertToBase(item.amount, from: item.currencyCode))
            categoryData[categoryName, default: 0] += amount
        }

        return categoryData
    }
}

// MARK: - Extensions

extension PieChartDataService {
    /// Convenience method to get the top categories
    /// - Parameters:
    ///   - items: Array of items to process
    ///   - dataType: Whether to show expenses or income
    ///   - timePeriod: Time period for filtering
    ///   - limit: Maximum number of categories to return
    ///   - payCycleStartDay: The start day of the financial month (1-28, defaults to 1)
    /// - Returns: Array of the top categories by amount
    func getTopCategories(
        from items: [TransactionSnapshot],
        for dataType: PieChartDataType,
        timePeriod: TimePeriod,
        limit: Int = 5,
        payCycleStartDay: Int = 1
    ) -> [PieChartDataPoint] {
        let allData = generatePieChartData(from: items, for: dataType, timePeriod: timePeriod, payCycleStartDay: payCycleStartDay)
        return Array(allData.prefix(limit))
    }
}