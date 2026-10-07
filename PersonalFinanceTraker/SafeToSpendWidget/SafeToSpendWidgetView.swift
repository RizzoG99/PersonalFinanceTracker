//
//  SafeToSpendWidgetView.swift
//  SafeToSpendWidget
//

import Foundation
import SwiftUI
import WidgetKit

struct SafeToSpendWidgetView: View {
    let entry: SafeToSpendEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "widget.safe_to_spend.title"), systemImage: "wallet.bifold")
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            if let amount = entry.amount, !entry.needsRefresh {
                Text(formattedAmount(amount))
                    .font(.title.bold())
                    .foregroundStyle(amount < 0 ? Color("negative") : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .monospacedDigit()
                    .privacySensitive()

                Spacer(minLength: 0)

                Text(caption(for: amount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(String(localized: "widget.safe_to_spend.unavailable"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(String(localized: "widget.safe_to_spend.open_app_to_refresh"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

        }
        .accessibilityElement(children: .combine)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "personalfinancetraker://home"))
    }

    /// Same wording as Home's hero: per-day figure only while there's something to spread.
    private func caption(for amount: Decimal) -> String {
        let payday = entry.payday.formatted(.dateTime.day().month(.abbreviated))
        if amount < 0 { return String(localized: "widget.safe_to_spend.over_plan \(payday)") }
        guard let perDay = SafeToSpendSnapshot.perDay(amount, from: entry.date, until: entry.payday) else {
            return String(localized: "widget.safe_to_spend.until \(payday)")
        }
        let daily = perDay.formatted(.currency(code: entry.currencyCode).precision(.fractionLength(0)))
        return String(localized: "widget.safe_to_spend.until_per_day \(payday) \(daily)")
    }

    private func formattedAmount(_ amount: Decimal, locale: Locale = .current) -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.locale = locale
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.usesGroupingSeparator = false

        guard let decimalAmount = numberFormatter.string(from: NSDecimalNumber(decimal: amount)) else {
            return amount.formatted(.currency(code: entry.currencyCode).precision(.fractionLength(2)))
        }

        let decimalSeparator = numberFormatter.decimalSeparator ?? "."
        let components = decimalAmount.split(separator: decimalSeparator.first ?? ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integerPart = String(components.first ?? "0")
        let sign = integerPart.hasPrefix("-") ? "-" : ""
        let digits = sign.isEmpty ? integerPart : String(integerPart.dropFirst())
        let groupingSeparator = numberFormatter.groupingSeparator ?? ","
        let groupedDigits = String(digits.reversed().enumerated().reduce(into: "") { result, element in
            if element.offset > 0, element.offset.isMultiple(of: 3) {
                result += groupingSeparator
            }
            result.append(element.element)
        }.reversed())
        let fractionalPart = components.count > 1 ? String(components[1]) : "00"

        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .currency
        currencyFormatter.currencyCode = entry.currencyCode
        currencyFormatter.locale = locale
        let currencySymbol = currencyFormatter.currencySymbol ?? entry.currencyCode

        return "\(sign)\(groupedDigits)\(decimalSeparator)\(fractionalPart) \(currencySymbol)"
    }
}
