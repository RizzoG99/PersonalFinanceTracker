//
//  ActivityRow.swift
//  PersonalFinanceTraker
//

import Foundation
import SwiftData

/// A travel folder as the Activity list sees it: name, running total, and the
/// day it anchors to. Derived per grouping pass, never persisted.
struct TravelSummary: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let symbolName: String
    /// Signed sum of the members, so a refund inside a trip reduces the total.
    let total: Decimal
    let count: Int
    /// Day section the row sits in: the most recent member, or — for a travel with
    /// no members yet — the day it was created, so it stays findable.
    let anchorDate: Date
    /// First and last member. The row sits in one day section but can span many, so
    /// the row itself has to say when the trip happened. Nil while the travel is empty.
    let startDate: Date?
    let endDate: Date?

    init(
        id: UUID,
        name: String,
        symbolName: String,
        total: Decimal,
        count: Int,
        anchorDate: Date,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.total = total
        self.count = count
        self.anchorDate = anchorDate
        self.startDate = startDate
        self.endDate = endDate
    }
}

/// One row in the Activity list: either a plain transaction, or a collapsed travel.
enum ActivityRow: Identifiable, Sendable, Hashable {
    case transaction(TransactionSnapshot)
    case travel(TravelSummary)

    enum ID: Hashable {
        case transaction(PersistentIdentifier)
        case travel(UUID)
    }

    var id: ID {
        switch self {
        case .transaction(let t): return .transaction(t.id)
        case .travel(let t): return .travel(t.id)
        }
    }

    var anchorDate: Date {
        switch self {
        case .transaction(let t): return t.timestamp
        case .travel(let t): return t.anchorDate
        }
    }

    var transaction: TransactionSnapshot? {
        if case .transaction(let t) = self { return t }
        return nil
    }
}

/// "1 expense" / "N expenses".
///
/// Deliberately not `^[\(count) expense](inflect: true)`: automatic grammar agreement is
/// resolved when a key is extracted into a String Catalog, so with runtime interpolation
/// through `String(localized:)` the markup reaches the screen verbatim.
enum TravelCountLabel {
    static func text(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 expense")
            : String(localized: "\(count) expenses")
    }

    static func days(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 day")
            : String(localized: "\(count) days")
    }
}

enum ActivityRowGrouper {
    /// Groups transactions into day sections, collapsing each travel's members into a
    /// single row anchored to the most recent member.
    ///
    /// Passing an empty `travels` yields nothing but `.transaction` rows — that is how
    /// callers opt out of collapsing while searching, filtering or multi-selecting,
    /// which keeps every existing filter and selection path working on plain rows.
    ///
    /// Empty travels are left out: Activity is a log of what happened, and a folder with
    /// nothing in it is not an event. The Travels screen passes `includeEmpty: true` —
    /// that is where a trip you have not spent on yet belongs.
    nonisolated static func group(
        _ items: [TransactionSnapshot],
        travels: [TravelSnapshot] = [],
        includeEmpty: Bool = false
    ) -> [(String, [ActivityRow])] {
        let calendar = Calendar.current
        let byId = Dictionary(uniqueKeysWithValues: travels.map { ($0.id, $0) })

        var members: [UUID: [TransactionSnapshot]] = [:]
        var rows: [ActivityRow] = []

        for item in items {
            // A travelId with no matching travel (deleted mid-flight, or restored from a
            // partial backup) falls through as a plain row rather than vanishing.
            if let travelId = item.travelId, byId[travelId] != nil {
                members[travelId, default: []].append(item)
            } else {
                rows.append(.transaction(item))
            }
        }

        for travel in travels {
            let group = members[travel.id] ?? []
            if group.isEmpty && !includeEmpty { continue }
            let dates = group.map(\.timestamp)
            rows.append(.travel(TravelSummary(
                id: travel.id,
                name: travel.name,
                symbolName: travel.symbolName,
                total: group.reduce(Decimal(0)) { $0 + $1.amount },
                count: group.count,
                anchorDate: dates.max() ?? travel.createdAt,
                startDate: dates.min(),
                endDate: dates.max()
            )))
        }

        let byDay = Dictionary(grouping: rows) { calendar.startOfDay(for: $0.anchorDate) }

        return byDay
            .sorted { $0.key > $1.key }
            .map { (day, rows) in
                (day.formattedForTransaction(), rows.sorted { $0.anchorDate > $1.anchorDate })
            }
    }
}
