//
//  PieChartDataPoint.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import Foundation
import SwiftUI

/// Represents a single data point in a pie chart for category-based financial analysis
///
/// This structure encapsulates financial data for a specific category,
/// including the category name, total amount, and calculated percentage.
///
/// ## Usage
/// ```swift
/// let dataPoint = PieChartDataPoint(
///     category: "Food",
///     amount: 500.00,
///     color: .blue
/// )
/// ```
public struct PieChartDataPoint: Identifiable {
    /// Unique identifier for the data point
    public let id = UUID()
    
    /// The category name this data point represents
    public let category: String
    
    /// Total amount for this category
    public let amount: Decimal
    
    /// Color to display for this category in the chart
    public let color: Color
    
    /// Percentage of total amount (calculated when generating chart data)
    public let percentage: Double
    
    /// Monthly budget for this category
    public let budget: Decimal?
    
    /// The actual category model
    public let categoryModel: CategoryModel?
    
    /// Creates a new pie chart data point
    /// - Parameters:
    ///   - category: The category name
    ///   - amount: Total amount for the category
    ///   - color: Color for the chart segment
    ///   - percentage: Percentage of total (0-100)
    ///   - budget: Optional monthly budget
    ///   - categoryModel: Optional CategoryModel
    public init(category: String, amount: Decimal, color: Color, percentage: Double = 0, budget: Decimal? = nil, categoryModel: CategoryModel? = nil) {
        self.category = category
        self.amount = amount
        self.color = color
        self.percentage = percentage
        self.budget = budget
        self.categoryModel = categoryModel
    }
    
    /// Whether this category has any financial activity
    public var hasActivity: Bool {
        return amount > 0
    }
    
    /// Formatted percentage string
    public var formattedPercentage: String {
        return String(format: "%.1f%%", percentage)
    }
    
    /// Budget usage percentage (0-1.0+)
    public var budgetUsage: Double? {
        guard let budget = budget, budget > 0 else { return nil }
        return Double(truncating: (amount / budget) as NSDecimalNumber)
    }
}

/// Type of data to display in the pie chart
public enum PieChartDataType {
    case expenses
    case income
    
    /// Human-readable description
    var description: String {
        switch self {
        case .expenses: return "Expenses"
        case .income: return "Income"
        }
    }
}