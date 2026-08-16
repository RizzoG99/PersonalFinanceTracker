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
        .configurationDisplayName("widget.seven_day_forecast.configuration_title")
        .description("widget.seven_day_forecast.configuration_description")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct SafeToSpendWidgetBundle: WidgetBundle {
    var body: some Widget {
        SafeToSpendWidget()
    }
}
