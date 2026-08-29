//
//  DailyLoggingHabitWidget.swift
//  PersonalFinanceTrakerWidget
//

import AppIntents
import Foundation
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
    let checkInState: String?
    let checkInStreakDays: Int?
    let quickTemplates: [HabitWidgetQuickTemplate]
    let lastUpdated: Date

    static let empty = HabitWidgetSnapshot(
        hasLoggedToday: false,
        todayCount: 0,
        currentStreakDays: 0,
        checkInState: "pending",
        checkInStreakDays: 0,
        quickTemplates: [],
        lastUpdated: .distantPast
    )

    var resolvedCheckInState: HabitWidgetCheckInState {
        HabitWidgetCheckInState(rawValue: checkInState ?? "")
            ?? (hasLoggedToday ? .transactionLogged : .pending)
    }

    var resolvedCheckInStreakDays: Int {
        checkInStreakDays ?? currentStreakDays
    }
}

private enum HabitWidgetCheckInState: String {
    case pending
    case transactionLogged
    case noSpendConfirmed

    var isComplete: Bool {
        self != .pending
    }
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

private struct HabitEntry: TimelineEntry {
    let date: Date
    let snapshot: HabitWidgetSnapshot
}

private enum HabitWidgetDeepLink {
    static let addTransaction = URL(string: "personalfinancetraker://add-transaction")!

    static func reviewTransaction(for template: HabitWidgetQuickTemplate) -> URL {
        var components = URLComponents()
        components.scheme = "personalfinancetraker"
        components.host = "review-transaction"
        components.queryItems = [
            URLQueryItem(name: "amount", value: String(template.amount)),
            URLQueryItem(name: "isExpense", value: String(template.isExpense)),
            URLQueryItem(name: "category", value: template.category),
            URLQueryItem(name: "note", value: template.note),
        ]
        return components.url ?? addTransaction
    }
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
            Text(smallStatusTitle)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text("\(entry.snapshot.resolvedCheckInStreakDays) days in a row")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !entry.snapshot.resolvedCheckInState.isComplete {
                Link(destination: HabitWidgetDeepLink.addTransaction) {
                    widgetActionLabel("Add", systemImage: "plus.circle.fill")
                }
                .accessibilityLabel(Text("Add transaction"))
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader

            if entry.snapshot.resolvedCheckInState.isComplete {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    statusMetric {
                        Text(completionMetricTitle)
                    }
                    statusMetric {
                        Text("\(entry.snapshot.resolvedCheckInStreakDays) days")
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("\(entry.snapshot.resolvedCheckInStreakDays) days in a row")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let template = entry.snapshot.quickTemplates.first {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Suggested transaction")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Text(template.label)
                                .font(.subheadline)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Link(destination: HabitWidgetDeepLink.reviewTransaction(for: template)) {
                                widgetActionLabel("Review", systemImage: "arrow.right.circle.fill")
                            }
                            .accessibilityLabel(Text("Review suggested transaction"))
                            .accessibilityInputLabels([
                                Text("Review"),
                            ])
                        }
                    }
                } else {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(statusTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Link(destination: HabitWidgetDeepLink.addTransaction) {
                            widgetActionLabel("Add", systemImage: "plus.circle.fill")
                        }
                        .accessibilityLabel(Text("Add transaction"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private func widgetActionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: 40)
            .background(Color("accentIndigo"), in: Capsule())
    }

    private func statusMetric<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessory: some View {
        Gauge(value: Double(entry.snapshot.resolvedCheckInStreakDays), in: 0...7) {
            Image(systemName: entry.snapshot.resolvedCheckInState.isComplete ? "checkmark" : "circle.dotted")
        } currentValueLabel: {
            Text("\(entry.snapshot.resolvedCheckInStreakDays)")
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(.background, for: .widget)
    }

    private var statusHeader: some View {
        Label(
            family == .systemSmall ? "Check-in" : "Financial Pulse",
            systemImage: entry.snapshot.resolvedCheckInState.isComplete ? "checkmark.circle.fill" : "circle.dotted.circle"
        )
        .font(.headline)
    }

    private var statusTitle: LocalizedStringKey {
        switch entry.snapshot.resolvedCheckInState {
        case .pending:
            "Check in today"
        case .transactionLogged:
            "\(entry.snapshot.todayCount) transactions today"
        case .noSpendConfirmed:
            "Nothing to add today"
        }
    }

    private var smallStatusTitle: LocalizedStringKey {
        switch entry.snapshot.resolvedCheckInState {
        case .pending:
            "Still to do"
        case .transactionLogged:
            "\(entry.snapshot.todayCount) transactions"
        case .noSpendConfirmed:
            "No spending"
        }
    }

    private var completionMetricTitle: LocalizedStringKey {
        switch entry.snapshot.resolvedCheckInState {
        case .transactionLogged:
            "\(entry.snapshot.todayCount) transactions"
        case .noSpendConfirmed:
            "No spending"
        case .pending:
            "Check in today"
        }
    }
}

struct DailyLoggingHabitWidget: Widget {
    let kind = "DailyLoggingHabitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitTimelineProvider()) { entry in
            DailyLoggingHabitWidgetView(entry: entry)
        }
        .configurationDisplayName("Financial Pulse")
        .description("Keep a private daily money check-in without showing amounts.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

@main
struct PersonalFinanceTrakerWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyLoggingHabitWidget()
        ScanReceiptWidget()
    }
}
