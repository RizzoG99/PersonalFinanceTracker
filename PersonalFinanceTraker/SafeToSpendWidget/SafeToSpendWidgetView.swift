//
//  SafeToSpendWidgetView.swift
//  SafeToSpendWidget
//

import SwiftUI
import WidgetKit

struct SafeToSpendWidgetView: View {
    let entry: SafeToSpendEntry

    var body: some View {
        VStack(alignment: .leading) {
            Label(String(localized: "widget.seven_day_forecast.title"), systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let amount = entry.amount, !entry.needsRefresh {
                Text(amount, format: .currency(code: entry.currencyCode).precision(.fractionLength(2)))
                    .font(.title2.bold())
                    .foregroundStyle(amount < 0 ? .red : .primary)
                    .lineLimit(1)
                    .privacySensitive()
                Text(String(localized: "widget.seven_day_forecast.through \(entry.forecastEnd.formatted(.dateTime.day().month(.abbreviated)))"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
                Text(String(localized: "widget.seven_day_forecast.open_app_to_refresh"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
