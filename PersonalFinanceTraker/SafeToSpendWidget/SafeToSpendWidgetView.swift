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
            Label(String(localized: "widget.seven_day_forecast.title"), systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            if let amount = entry.amount, !entry.needsRefresh {
                Text(formattedAmount(amount))
                    .font(.title.bold())
                    .foregroundStyle(amount < 0 ? Color("negative") : Color("positive"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .monospacedDigit()
                    .privacySensitive()

                Spacer(minLength: 0)

                Text(String(localized: "widget.seven_day_forecast.on \(entry.forecastEnd.formatted(.dateTime.day().month(.abbreviated)))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(String(localized: "widget.seven_day_forecast.unavailable"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(String(localized: "widget.seven_day_forecast.open_app_to_refresh"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

        }
        .accessibilityElement(children: .combine)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "personalfinancetraker://insights"))
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
