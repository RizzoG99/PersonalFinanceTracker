//
//  ScanReceiptWidget.swift
//  PersonalFinanceTrakerWidget
//
//  Tap-anywhere widget: opens the app straight into the receipt camera
//  (personalfinancetraker://scan-receipt), skipping the source-choice dialog.
//

import SwiftUI
import WidgetKit

private struct ScanReceiptEntry: TimelineEntry {
    let date: Date
}

private struct ScanReceiptProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScanReceiptEntry { ScanReceiptEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (ScanReceiptEntry) -> Void) {
        completion(ScanReceiptEntry(date: .now))
    }

    // ponytail: static content, so one entry that never expires.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ScanReceiptEntry>) -> Void) {
        completion(Timeline(entries: [ScanReceiptEntry(date: .now)], policy: .never))
    }
}

private struct ScanReceiptWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Image(systemName: "doc.text.viewfinder")
                    .font(.title2)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.largeTitle)
                        .foregroundStyle(Color("accentIndigo"))
                    Spacer(minLength: 0)
                    Text("Scan receipt")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("Opens the camera")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: "personalfinancetraker://scan-receipt"))
        .accessibilityLabel(Text("Scan receipt"))
        .containerBackground(.background, for: .widget)
    }
}

struct ScanReceiptWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScanReceiptWidget", provider: ScanReceiptProvider()) { _ in
            ScanReceiptWidgetView()
        }
        .configurationDisplayName("Scan Receipt")
        .description("Open the receipt camera in one tap.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
