//
//  SafeToSpendSnapshot.swift
//  PersonalFinanceTraker
//
//  Lives in Shared/ — an Xcode synced group compiled into both the app target
//  and SafeToSpendWidgetExtension.
//

import Foundation

struct SafeToSpendDayValue: Codable, Sendable, Equatable {
    let date: Date
    let amount: Decimal
}

struct SafeToSpendSnapshot: Codable, Sendable, Equatable {
    let generatedAt: Date
    let currencyCode: String
    let days: [SafeToSpendDayValue]

    private static let fileName = "safe_to_spend_snapshot.json"

    private static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
    }

    func write() throws {
        guard let dir = Self.containerURL() else {
            throw SafeToSpendSnapshotError.noContainer
        }
        let url = dir.appendingPathComponent(Self.fileName)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func load() -> SafeToSpendSnapshot? {
        guard let dir = containerURL() else { return nil }
        let url = dir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SafeToSpendSnapshot.self, from: data)
    }

    /// Returns the safe-to-spend amount for `date`, or nil if the snapshot is missing,
    /// undecodable, or `date` falls outside the cached days — callers must render the
    /// neutral empty state in every one of those cases, never the last known value.
    static func amount(for date: Date, from snapshot: SafeToSpendSnapshot?, calendar: Calendar = .current) -> Decimal? {
        guard let snapshot else { return nil }
        let day = calendar.startOfDay(for: date)
        return snapshot.days.first { calendar.isDate($0.date, inSameDayAs: day) }?.amount
    }
}

enum SafeToSpendSnapshotError: Error {
    case noContainer
}
