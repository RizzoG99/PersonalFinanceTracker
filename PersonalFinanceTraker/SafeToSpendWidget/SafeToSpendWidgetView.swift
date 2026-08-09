//
//  SafeToSpendWidgetView.swift
//  SafeToSpendWidget
//

import SwiftUI
import WidgetKit

struct SafeToSpendWidgetView: View {
    let entry: SafeToSpendEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "banknote.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Safe to spend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let amount = entry.amount {
                Text(compactAmount(amount, currencyCode: entry.currencyCode))
                    .font(.title2.bold())
                    .foregroundStyle(amount < 0 ? .red : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .privacySensitive()
                Text(entry.payCycleEnd, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Log a transaction")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// Widget-local compact formatting: no cent precision below 1000 either, so the
    /// amount never wraps onto a second line in the small widget's tight width — the
    /// app-wide `formattedEURCompact` only compacts at >=1000 and shows full cents
    /// below that, which is fine for in-app UI but wraps awkwardly here.
    private func compactAmount(_ amount: Decimal, currencyCode: String) -> String {
        if abs((amount as NSDecimalNumber).doubleValue) >= 1000 {
            return amount.formattedEURCompact(currency: currencyCode)
        }
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = currencyCode
        fmt.maximumFractionDigits = 0
        fmt.minimumFractionDigits = 0
        return fmt.string(from: amount as NSDecimalNumber) ?? amount.formattedEURCompact(currency: currencyCode)
    }
}
