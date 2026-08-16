//
//  SafeToSpendProvider.swift
//  SafeToSpendWidget
//

import Foundation
import WidgetKit

struct SafeToSpendProvider: TimelineProvider {
    func placeholder(in context: Context) -> SafeToSpendEntry {
        SafeToSpendEntry(
            date: .now,
            amount: 120,
            currencyCode: "EUR",
            forecastEnd: Calendar.current.date(byAdding: .day, value: 6, to: .now) ?? .now,
            needsRefresh: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SafeToSpendEntry) -> Void) {
        completion(makeEntry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SafeToSpendEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date.now
        let startOfToday = calendar.startOfDay(for: now)
        let entries = (0..<7).map { offset in
            makeEntry(for: calendar.date(byAdding: .day, value: offset, to: startOfToday) ?? startOfToday)
        }
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let nextRefresh = calendar.date(byAdding: .second, value: 1, to: nextMidnight) ?? nextMidnight
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    private func makeEntry(for date: Date) -> SafeToSpendEntry {
        let snapshot = SafeToSpendSnapshot.load()
        let amount = SafeToSpendSnapshot.projectedAmount(for: date, from: snapshot)
        return SafeToSpendEntry(
            date: date,
            amount: amount,
            currencyCode: snapshot?.currencyCode ?? "EUR",
            forecastEnd: snapshot?.forecastEnd ?? date,
            needsRefresh: amount == nil
        )
    }
}
