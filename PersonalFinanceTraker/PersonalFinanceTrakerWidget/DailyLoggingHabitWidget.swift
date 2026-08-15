//
//  DailyLoggingHabitWidget.swift
//  PersonalFinanceTrakerWidget
//

import AppIntents
import SwiftUI
import WidgetKit

private struct HabitWidgetQuickTemplate: Identifiable, Codable {
    var id: String { [label, category, note, currencyCode, String(isExpense), String(amount)].joined(separator: "|") }

    let label: String
    let amount: Double
    let isExpense: Bool
    let category: String
    let note: String
    let currencyCode: String
}

private struct HabitWidgetSnapshot: Codable {
    let hasLoggedToday: Bool
    let todayCount: Int
    let currentStreakDays: Int
    let quickTemplates: [HabitWidgetQuickTemplate]
    let lastUpdated: Date

    static let empty = HabitWidgetSnapshot(
        hasLoggedToday: false,
        todayCount: 0,
        currentStreakDays: 0,
        quickTemplates: [],
        lastUpdated: .distantPast
    )
}

private enum HabitWidgetSnapshotStore {
    static let appGroupIdentifier = "group.rizzoG99.PersonalFinanceTraker"
    private static let key = "dailyLoggingHabitSnapshot"

    static func load() -> HabitWidgetSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(HabitWidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}

private struct PendingHabitTemplateRequest: Codable {
    let amount: Double
    let isExpense: Bool
    let category: String
    let note: String
    let createdAt: Date
}

private enum PendingHabitTemplateStore {
    private static let key = "pendingHabitTemplateRequest"

    static func save(_ request: PendingHabitTemplateRequest) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        defaults.set(data, forKey: key)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: HabitWidgetSnapshotStore.appGroupIdentifier) ?? .standard
    }
}

private enum PendingHabitAddStore {
    private static let key = "pendingHabitAddRequest"

    static func save() {
        defaults.set(true, forKey: key)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: HabitWidgetSnapshotStore.appGroupIdentifier) ?? .standard
    }
}

struct OpenAddTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Transaction"
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        PendingHabitAddStore.save()
        return .result()
    }
}

struct QueueRepeatTemplateIntent: AppIntent {
    static let title: LocalizedStringResource = "Repeat Transaction"
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Is Expense")
    var isExpense: Bool

    @Parameter(title: "Category")
    var category: String

    @Parameter(title: "Note")
    var note: String

    init() {}

    fileprivate init(template: HabitWidgetQuickTemplate) {
        amount = template.amount
        isExpense = template.isExpense
        category = template.category
        note = template.note
    }

    func perform() async throws -> some IntentResult {
        PendingHabitTemplateStore.save(PendingHabitTemplateRequest(
            amount: amount,
            isExpense: isExpense,
            category: category,
            note: note,
            createdAt: .now
        ))
        return .result()
    }
}

private struct HabitEntry: TimelineEntry {
    let date: Date
    let snapshot: HabitWidgetSnapshot
}

private struct HabitTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> Void) {
        completion(HabitEntry(date: .now, snapshot: HabitWidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> Void) {
        let entry = HabitEntry(date: .now, snapshot: HabitWidgetSnapshotStore.load())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

private struct DailyLoggingHabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HabitEntry

    var body: some View {
        switch family {
        case .systemMedium:
            medium
        case .accessoryCircular:
            accessory
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusHeader
            Spacer(minLength: 0)
            Text(entry.snapshot.hasLoggedToday ? "\(entry.snapshot.todayCount) today" : "Log")
                .font(.headline)
            Text("\(entry.snapshot.currentStreakDays)d streak")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(intent: OpenAddTransactionIntent()) {
                Text("Log")
            }
            .buttonStyle(.borderedProminent)
        }
        .containerBackground(.background, for: .widget)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader
            HStack(spacing: 8) {
                Text("\(entry.snapshot.todayCount) today")
                Text("\(entry.snapshot.currentStreakDays)d streak")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(entry.snapshot.quickTemplates.prefix(3)) { template in
                    Button(intent: QueueRepeatTemplateIntent(template: template)) {
                        Text(template.label)
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var accessory: some View {
        Gauge(value: Double(entry.snapshot.currentStreakDays), in: 0...7) {
            Image(systemName: entry.snapshot.hasLoggedToday ? "checkmark" : "plus")
        } currentValueLabel: {
            Text("\(entry.snapshot.currentStreakDays)")
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(.background, for: .widget)
    }

    private var statusHeader: some View {
        Label(
            entry.snapshot.hasLoggedToday ? "Logged today" : "Log today",
            systemImage: entry.snapshot.hasLoggedToday ? "checkmark.circle.fill" : "plus.circle.fill"
        )
        .font(.headline)
    }
}

struct DailyLoggingHabitWidget: Widget {
    let kind = "DailyLoggingHabitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitTimelineProvider()) { entry in
            DailyLoggingHabitWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Logging")
        .description("Track today's logging status and streak without showing amounts.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

@main
struct PersonalFinanceTrakerWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyLoggingHabitWidget()
    }
}
