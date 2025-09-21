//
//  FinancialSummaryCard.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI

/// A reusable card component that displays financial summary information
///
/// This component presents income, expenses, and balance in a clean, organized layout
/// with proper color coding and typography hierarchy.
///
/// ## Usage
/// ```swift
/// FinancialSummaryCard(
///     income: 5000.00,
///     expenses: -3000.00,
///     currencyCode: "EUR"
/// )
/// ```
///
/// ## Features
/// - Color-coded amounts (green for income, red for expenses, dynamic for balance)
/// - Proper typography hierarchy
/// - Consistent spacing and layout
/// - Support for different currencies
/// - Automatic balance calculation
public struct FinancialSummaryCard: View {
    /// Total income amount
    public let income: Decimal
    
    /// Total expenses amount (typically negative)
    public let expenses: Decimal
    
    /// Currency code for formatting (e.g., "EUR", "USD")
    public let currencyCode: String
    
    /// Calculated net balance
    private var balance: Decimal {
        income - abs(expenses)
    }
    
    /// Creates a new financial summary card
    /// - Parameters:
    ///   - income: Total income amount
    ///   - expenses: Total expenses amount (typically negative)
    ///   - currencyCode: Currency code for formatting (defaults to "EUR")
    public init(income: Decimal, expenses: Decimal, currencyCode: String = "EUR") {
        self.income = income
        self.expenses = expenses
        self.currencyCode = currencyCode
    }
    
    public var body: some View {
        VStack(alignment: .trailing, spacing: 24) {
            VStack(spacing: 0) {
                HStack {
                    Text("Income")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(income, format: .currency(code: currencyCode))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                Spacer()
                HStack {
                    Text("Expenses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(expenses, format: .currency(code: currencyCode))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }
            
            Divider()
            
            HStack {
                Text("Balance")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(balance, format: .currency(code: currencyCode))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(balance >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview("Positive Balance") {
    FinancialSummaryCard(
        income: 5000.00,
        expenses: -3000.00,
        currencyCode: "EUR"
    )
    .padding()
}

#Preview("Negative Balance") {
    FinancialSummaryCard(
        income: 2000.00,
        expenses: -3000.00,
        currencyCode: "USD"
    )
    .padding()
}

#Preview("Zero Balance") {
    FinancialSummaryCard(
        income: 3000.00,
        expenses: -3000.00,
        currencyCode: "GBP"
    )
    .padding()
}