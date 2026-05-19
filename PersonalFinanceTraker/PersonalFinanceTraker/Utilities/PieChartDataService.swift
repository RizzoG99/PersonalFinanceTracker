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
    /// - Returns: Array of pie chart data points ready for display
    public func generatePieChartData(
        from items: [TransactionModel],
        for dataType: PieChartDataType,
        timePeriod: TimePeriod,
        referenceDate: Date = Date()
    ) -> [PieChartDataPoint] {
        
        // Filter items by time period and transaction type
        let filteredItems = filterItems(items, for: timePeriod, referenceDate: referenceDate)
        let typeFilteredItems = filterByDataType(filteredItems, dataType: dataType)
        
        // Group by category and calculate totals
        let categoryGroupedData = groupByCategoryModels(typeFilteredItems)
        
        // Calculate total amount for percentage calculations
        let totalAmount = categoryGroupedData.values.map { $0.total }.reduce(0, +)
        
        // Generate pie chart data points
        var pieChartData: [PieChartDataPoint] = []
        
        for (index, (categoryName, data)) in categoryGroupedData.sorted(by: { $0.value.total > $1.value.total }).enumerated() {
            let percentage = totalAmount > 0 ? Double(truncating: (data.total / totalAmount * 100) as NSDecimalNumber) : 0
            let color = categoryColors[index % categoryColors.count]
            
            pieChartData.append(PieChartDataPoint(
                category: categoryName,
                amount: data.total,
                color: color,
                percentage: percentage,
                budget: data.model?.monthlyBudget,
                categoryModel: data.model
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
    /// - Returns: A tuple containing total amount and number of categories
    public func getSummaryStats(
        from items: [TransactionModel],
        for dataType: PieChartDataType,
        timePeriod: TimePeriod,
        referenceDate: Date = Date()
    ) -> (totalAmount: Decimal, categoryCount: Int) {
        
        let filteredItems = filterItems(items, for: timePeriod, referenceDate: referenceDate)
        let typeFilteredItems = filterByDataType(filteredItems, dataType: dataType)
        let categoryTotals = groupByCategoryModels(typeFilteredItems)
        
        let totalAmount = categoryTotals.values.map { $0.total }.reduce(0, +)
        
        return (totalAmount: totalAmount, categoryCount: categoryTotals.count)
    }
    
    // MARK: - Private Methods
    
    /// Filters items based on the specified time period
    /// - Parameters:
    ///   - items: Array of items to filter
    ///   - timePeriod: Time period for filtering
    ///   - referenceDate: Reference date for calculations
    /// - Returns: Filtered array of items within the time period
    private func filterItems(_ items: [TransactionModel], for timePeriod: TimePeriod, referenceDate: Date) -> [TransactionModel] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -timePeriod.days, to: referenceDate) ?? referenceDate
        
        return items.filter { item in
            item.timestamp >= startDate && item.timestamp <= referenceDate
        }
    }
    
    /// Filters items by data type (expenses or income)
    /// - Parameters:
    ///   - items: Array of items to filter
    ///   - dataType: Type of data to include
    /// - Returns: Filtered array of items
    private func filterByDataType(_ items: [TransactionModel], dataType: PieChartDataType) -> [TransactionModel] {
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
    private func groupByCategoryModels(_ items: [TransactionModel]) -> [String: (total: Decimal, model: CategoryModel?)] {
        var categoryData: [String: (total: Decimal, model: CategoryModel?)] = [:]
        
        for item in items {
            let categoryName = item.category.isEmpty ? "Other" : item.category
            let amount = abs(currencyService.convertToBase(item.amount, from: item.currencyCode))
            
            if let existing = categoryData[categoryName] {
                categoryData[categoryName] = (existing.total + amount, existing.model ?? item.categoryModel)
            } else {
                categoryData[categoryName] = (amount, item.categoryModel)
            }
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
    /// - Returns: Array of the top categories by amount
    public func getTopCategories(
        from items: [TransactionModel],
        for dataType: PieChartDataType,
        timePeriod: TimePeriod,
        limit: Int = 5
    ) -> [PieChartDataPoint] {
        let allData = generatePieChartData(from: items, for: dataType, timePeriod: timePeriod)
        return Array(allData.prefix(limit))
    }
}