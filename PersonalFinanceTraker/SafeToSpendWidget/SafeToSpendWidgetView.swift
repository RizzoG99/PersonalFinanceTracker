//
//  SafeToSpendWidgetView.swift
//  SafeToSpendWidget
//

import Foundation
import SwiftUI
import WidgetKit

/// Same number and wording as Home's Safe to Spend hero (#190).
struct SafeToSpendWidgetView: View {
    let entry: SafeToSpendEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(String(localized: "widget.safe_to_spend.title"), systemImage: "wallet.bifold")
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .widgetAccentable()

            Spacer(minLength: 0)

            if let amount = entry.amount, !entry.needsRefresh {
                if entry.hasIncome {
                    figures(amount)
                } else {
                    // Home asks for income here too: a bare "−spent" would read as overspending.
                    message(String(localized: "widget.safe_to_spend.no_income"))
                }
            } else {
                message(String(localized: "widget.safe_to_spend.unavailable"),
                        detail: String(localized: "widget.safe_to_spend.open_app_to_refresh"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "personalfinancetraker://home"))
    }

    private func figures(_ amount: Decimal) -> some View {
        let lastDay = SafeToSpendSnapshot.lastDay(before: entry.payday).formatted(.dateTime.day().month(.abbreviated))
        let perDay = SafeToSpendSnapshot.perDay(amount, from: entry.date, until: entry.payday)
            .map { $0.formatted(.currency(code: entry.currencyCode).precision(.fractionLength(0))) }
        let until = amount < 0
            ? String(localized: "widget.safe_to_spend.over_plan \(lastDay)")
            : String(localized: "widget.safe_to_spend.until \(lastDay)")
        let formatted = amount.formatted(.currency(code: entry.currencyCode))
        var spoken = "\(formatted), \(until)"
        if let perDay { spoken += ", " + String(localized: "widget.safe_to_spend.per_day_spoken \(perDay)") }
        return VStack(alignment: .leading, spacing: 2) {
            Text(amount.formatted(.currency(code: entry.currencyCode)))
                .font(.title.bold())
                .foregroundStyle(amount < 0 ? Color("negative") : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .monospacedDigit()
            // Two lines, not one with "·": the per-day figure was the part getting truncated.
            Text(until)
                .font(.caption)
                .foregroundStyle(amount < 0 ? Color("negative") : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let perDay {
                Text(String(localized: "widget.safe_to_spend.per_day \(perDay)"))
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        // The per-day figure times the days left gives the amount away just the same.
        .privacySensitive()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    private func message(_ text: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
