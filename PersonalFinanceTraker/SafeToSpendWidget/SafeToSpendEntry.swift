//
//  SafeToSpendEntry.swift
//  SafeToSpendWidget
//

import WidgetKit

struct SafeToSpendEntry: TimelineEntry {
    let date: Date
    let amount: Decimal?
    let currencyCode: String
    let forecastEnd: Date
    let needsRefresh: Bool
}
