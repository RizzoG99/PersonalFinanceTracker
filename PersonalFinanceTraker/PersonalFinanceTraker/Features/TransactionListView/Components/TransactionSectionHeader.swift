//
//  TransactionSectionHeader.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI

/// A reusable header component for transaction list sections
///
/// This component displays the date and total amount for a group of transactions,
/// typically used as a section header in a List or LazyVStack.
///
/// ## Usage
/// ```swift
/// TransactionSectionHeader(
///     dateString: "Today",
///     totalAmount: 125.50,
///     currencyCode: "EUR"
/// )
/// ```
///
/// ## Features
/// - Displays formatted date string
/// - Shows total amount with proper currency formatting
/// - Consistent typography and spacing
/// - Color-coded totals (green for positive, red for negative)
public struct TransactionSectionHeader: View {
    /// The formatted date string to display
    public let dateString: String
    
    /// The total amount for this section
    public let totalAmount: Decimal
    
    /// Currency code for formatting
    public let currencyCode: String
    
    /// Creates a new transaction section header
    /// - Parameters:
    ///   - dateString: The formatted date string (e.g., "Today", "Yesterday", "Jan 15")
    ///   - totalAmount: The total amount for this section
    ///   - currencyCode: Currency code for formatting (defaults to "EUR")
    public init(dateString: String, totalAmount: Decimal, currencyCode: String = "EUR") {
        self.dateString = dateString
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
    }
    
    public var body: some View {
        HStack {
            Text(dateString)
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
//            Text(totalAmount, format: .currency(code: currencyCode))
//                .font(.subheadline)
//                .fontWeight(.medium)
//                .foregroundColor(totalAmount >= 0 ? .green : .red)
        }
    }
}

#Preview("Positive Total") {
    TransactionSectionHeader(
        dateString: "Today",
        totalAmount: 125.50,
        currencyCode: "EUR"
    )
    .padding()
}

#Preview("Negative Total") {
    TransactionSectionHeader(
        dateString: "Yesterday",
        totalAmount: -75.25,
        currencyCode: "USD"
    )
    .padding()
}

#Preview("Zero Total") {
    TransactionSectionHeader(
        dateString: "January 15",
        totalAmount: 0.00,
        currencyCode: "GBP"
    )
    .padding()
}
