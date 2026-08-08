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
            Text("Safe to spend")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let amount = entry.amount {
                Text(amount.formattedEURCompact(currency: entry.currencyCode))
                    .font(.title2.bold())
                    .minimumScaleFactor(0.7)
            } else {
                Text("Open the app")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
