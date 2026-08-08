//
//  SafeToSpendProvider.swift
//  SafeToSpendWidget
//

import WidgetKit
import Foundation

struct SafeToSpendProvider: TimelineProvider {
    func placeholder(in context: Context) -> SafeToSpendEntry {
        SafeToSpendEntry(date: .now, amount: 120, currencyCode: "EUR")
    }

    func getSnapshot(in context: Context, completion: @escaping (SafeToSpendEntry) -> Void) {
        completion(makeEntry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SafeToSpendEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date.now
        let entries = (0..<7).map { offset -> SafeToSpendEntry in
            let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            return makeEntry(for: date)
        }
        // Periodic backstop: reload every few hours even without an app-triggered
        // WidgetCenter.reloadTimelines call, so day-rollover still shows the right
        // pre-computed number.
        let nextRefresh = calendar.date(byAdding: .hour, value: 4, to: now) ?? now
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    private func makeEntry(for date: Date) -> SafeToSpendEntry {
        let snapshot = SafeToSpendSnapshot.load()
        let amount = SafeToSpendSnapshot.amount(for: date, from: snapshot)
        return SafeToSpendEntry(date: date, amount: amount, currencyCode: snapshot?.currencyCode ?? "EUR")
    }
}
