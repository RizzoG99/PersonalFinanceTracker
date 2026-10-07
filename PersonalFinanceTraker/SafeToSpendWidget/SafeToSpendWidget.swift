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
        .configurationDisplayName("widget.safe_to_spend.configuration_title")
        .description("widget.safe_to_spend.configuration_description")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct SafeToSpendWidgetBundle: WidgetBundle {
    var body: some Widget {
        SafeToSpendWidget()
    }
}
