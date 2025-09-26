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
    
    /// Creates a new pie chart data point
    /// - Parameters:
    ///   - category: The category name
    ///   - amount: Total amount for the category
    ///   - color: Color for the chart segment
    ///   - percentage: Percentage of total (0-100)
    public init(category: String, amount: Decimal, color: Color, percentage: Double = 0) {
        self.category = category
        self.amount = amount
        self.color = color
        self.percentage = percentage
    }
    
    /// Whether this category has any financial activity
    public var hasActivity: Bool {
        return amount > 0
    }
    
    /// Formatted percentage string
    public var formattedPercentage: String {
        return String(format: "%.1f%%", percentage)
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