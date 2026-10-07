//
//  SafeToSpendEntry.swift
//  SafeToSpendWidget
//

import WidgetKit

struct SafeToSpendEntry: TimelineEntry {
    let date: Date
    let amount: Decimal?
    let currencyCode: String
    let payday: Date
    /// False when this cycle has no income: Home asks for income instead of showing a number.
    let hasIncome: Bool
    let needsRefresh: Bool
}
