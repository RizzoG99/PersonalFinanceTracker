//
//  SafeToSpendSnapshot.swift
//  PersonalFinanceTraker
//

import Foundation

struct SafeToSpendDayValue: Codable, Sendable, Equatable {
    let date: Date
    let amount: Decimal
}

struct SafeToSpendSnapshot: Codable, Sendable, Equatable {
    let generatedAt: Date
    let currencyCode: String
    let forecastEnd: Date
    let days: [SafeToSpendDayValue]

    private static let fileName = "safe_to_spend_snapshot.json"

    private static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
    }

    func write() throws {
        guard let directory = Self.containerURL() else {
            throw SafeToSpendSnapshotError.noContainer
        }
        let url = directory.appendingPathComponent(Self.fileName)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func load() -> SafeToSpendSnapshot? {
        guard let directory = containerURL() else { return nil }
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SafeToSpendSnapshot.self, from: data)
    }

    static func amount(for date: Date, from snapshot: SafeToSpendSnapshot?, calendar: Calendar = .current) -> Decimal? {
        guard let snapshot else { return nil }
        let day = calendar.startOfDay(for: date)
        return snapshot.days.first { calendar.isDate($0.date, inSameDayAs: day) }?.amount
    }

    /// Uses the forecast-end value until the precomputed forecast expires. After that
    /// point the widget must ask the app for a fresh snapshot instead of showing stale data.
    static func projectedAmount(
        for date: Date,
        from snapshot: SafeToSpendSnapshot?,
        calendar: Calendar = .current
    ) -> Decimal? {
        guard let snapshot,
              calendar.startOfDay(for: date) <= calendar.startOfDay(for: snapshot.forecastEnd) else {
            return nil
        }
        return amount(for: snapshot.forecastEnd, from: snapshot, calendar: calendar)
    }
}

enum SafeToSpendSnapshotError: Error {
    case noContainer
}
