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
            amount: 742,
            currencyCode: "EUR",
            payday: Calendar.current.date(byAdding: .day, value: 20, to: .now) ?? .now,
            hasIncome: true,
            needsRefresh: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SafeToSpendEntry) -> Void) {
        // The gallery preview shouldn't show the "open the app" state on a fresh install.
        completion(context.isPreview ? placeholder(in: context) : makeEntry(for: .now))
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
            payday: snapshot?.payday ?? date,
            hasIncome: snapshot?.hasIncome ?? true,
            needsRefresh: amount == nil
        )
    }
}
