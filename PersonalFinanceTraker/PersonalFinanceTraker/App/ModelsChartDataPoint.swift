//
//  ChartDataPoint.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import Foundation

/// Represents a single data point in financial charts
///
/// This structure encapsulates financial data for a specific time period,
/// including income, expenses, and calculated net amount.
///
/// ## Usage
/// ```swift
/// let dataPoint = ChartDataPoint(
///     period: "January",
///     income: 5000.00,
///     expenses: 3000.00
/// )
/// 
/// print("Net amount: \(dataPoint.netAmount)") // Prints: 2000.00
/// ```
public struct ChartDataPoint {
    /// The time period this data point represents (e.g., "Mon", "Week 1", "Jan")
    public let period: String
    
    /// Total income for this period
    public let income: Decimal
    
    /// Total expenses for this period (stored as positive value)
    public let expenses: Decimal
    
    /// Calculated net amount (income - expenses)
    public let netAmount: Decimal
    
    /// Creates a new chart data point
    /// - Parameters:
    ///   - period: The time period label (e.g., "Monday", "Week 1", "January")
    ///   - income: Total income for the period
    ///   - expenses: Total expenses for the period (should be positive)
    public init(period: String, income: Decimal, expenses: Decimal) {
        self.period = period
        self.income = income
        self.expenses = expenses
        self.netAmount = income - expenses
    }
    
    /// Whether this period has any financial activity
    public var hasActivity: Bool {
        return income > 0 || expenses > 0
    }
    
    /// Whether this period shows a profit (income > expenses)
    public var isProfit: Bool {
        return netAmount > 0
    }
    
    /// Whether this period shows a loss (expenses > income)
    public var isLoss: Bool {
        return netAmount < 0
    }
    
    /// Whether this period is break-even (income == expenses)
    public var isBreakEven: Bool {
        return netAmount == 0
    }
}