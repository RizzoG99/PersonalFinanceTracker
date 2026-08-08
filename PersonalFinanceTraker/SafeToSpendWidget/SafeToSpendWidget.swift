//
//  SafeToSpendWidget.swift
//  SafeToSpendWidget
//

import SwiftUI
import WidgetKit

struct SafeToSpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SafeToSpendWidgetKind.name, provider: SafeToSpendProvider()) { entry in
            SafeToSpendWidgetView(entry: entry)
        }
        .configurationDisplayName("Safe to Spend")
        .description("Shows how much you can safely spend until your next payday.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct SafeToSpendWidgetBundle: WidgetBundle {
    var body: some Widget {
        SafeToSpendWidget()
    }
}
