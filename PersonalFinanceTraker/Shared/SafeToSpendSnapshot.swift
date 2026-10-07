//
//  SafeToSpendSnapshot.swift
//  PersonalFinanceTraker
//

import Foundation

/// Safe to Spend until payday (#190), handed from the app to the widget through the app group.
struct SafeToSpendSnapshot: Codable, Sendable, Equatable {
    let generatedAt: Date
    let currencyCode: String
    let amount: Decimal
    /// Start of the next pay cycle — the amount covers every day before it.
    let payday: Date
    /// False when this cycle has no income — the amount is then just minus the spending.
    let hasIncome: Bool

    private static let fileName = "safe_to_spend_snapshot.json"

    private static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
    }

    func write() throws {
        guard let directory = Self.containerURL() else { throw SafeToSpendSnapshotError.noContainer }
        let url = directory.appendingPathComponent(Self.fileName)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// A snapshot written by an older build doesn't decode — the widget then asks for a refresh.
    static func load() -> SafeToSpendSnapshot? {
        guard let directory = containerURL() else { return nil }
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SafeToSpendSnapshot.self, from: data)
    }

    /// Days from `date` up to the day before payday, counting `date` itself; 0 once payday arrives.
    static func daysLeft(from date: Date, until payday: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: payday)).day
        return max(0, days ?? 0)
    }

    /// The amount stays valid until payday; from then on the widget must ask the app for a new cycle.
    static func projectedAmount(for date: Date, from snapshot: SafeToSpendSnapshot?, calendar: Calendar = .current) -> Decimal? {
        guard let snapshot, daysLeft(from: date, until: snapshot.payday, calendar: calendar) > 0 else { return nil }
        return snapshot.amount
    }

    /// The per-day figure in whole units, only while there is something left to spread.
    /// Rounded down: "€156/day" for €467 over 3 days would promise more than there is.
    static func perDay(_ amount: Decimal, from date: Date, until payday: Date, calendar: Calendar = .current) -> Decimal? {
        let days = daysLeft(from: date, until: payday, calendar: calendar)
        guard amount > 0, days > 0 else { return nil }
        var exact = amount / Decimal(days), rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 0, .down)
        return rounded
    }

    /// The last day the amount covers — "until 9 Oct" reads inclusive, payday itself isn't covered.
    static func lastDay(before payday: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -1, to: payday) ?? payday
    }
}

enum SafeToSpendSnapshotError: Error {
    case noContainer
}
