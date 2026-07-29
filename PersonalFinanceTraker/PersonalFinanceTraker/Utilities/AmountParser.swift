//  AmountParser.swift
//  PersonalFinanceTraker

import Foundation

/// Shared parse/format for user-entered Decimal amounts across the app's
/// money-input screens (Budgets, Amount filter, Goal funds, Credit card).
/// Not for `CurrencyAmountField` (Double-based) or `AddGoalSheet` (comma =
/// thousands separator there, not decimal) — both have different semantics.
enum AmountParser {
    /// European decimal-pad convention: comma is the decimal separator.
    /// Returns nil for empty/unparseable input; when requirePositive, also
    /// nil for values <= 0.
    static func parse(_ text: String, requirePositive: Bool = false) -> Decimal? {
        let normalized = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: normalized) else { return nil }
        if requirePositive && value <= 0 { return nil }
        return value
    }

    /// Currency display matching the convention already used by Budgets
    /// (`.formatted(.currency(code:))`).
    static func format(_ value: Decimal, currencyCode: String = "EUR") -> String {
        value.formatted(.currency(code: currencyCode))
    }
}
