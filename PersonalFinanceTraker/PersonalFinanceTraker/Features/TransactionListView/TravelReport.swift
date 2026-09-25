//
//  TravelReport.swift
//  PersonalFinanceTraker
//

import Foundation

/// What a trip actually cost, derived from its members. Pure value type: no fetching, no
/// view state, so the arithmetic can be tested on its own.
///
/// Money semantics follow the app's convention — expenses are negative, income positive:
/// - `spent` is the absolute value of the expenses only,
/// - `refunded` is any positive amount inside the trip (a friend paying you back),
/// - `net` is the signed sum, i.e. what the trip really cost you.
struct TravelReport: Equatable {
    let spent: Decimal
    let refunded: Decimal
    let net: Decimal
    let count: Int
    let startDate: Date?
    let endDate: Date?
    /// Inclusive days spanned by the trip; 1 for a single-day trip, 0 when there is nothing in it.
    let dayCount: Int
    /// Spending per day. Zero for an empty trip rather than a divide-by-zero.
    let perDay: Decimal
    /// Expense categories, biggest spend first. Refunds are excluded so a category
    /// cannot show a negative "spend".
    let categories: [CategorySpend]

    struct CategorySpend: Equatable, Identifiable {
        let category: String
        let amount: Decimal
        var id: String { category }
    }

    init(members: [TransactionSnapshot], calendar: Calendar = .current) {
        count = members.count

        var spentTotal = Decimal(0)
        var refundedTotal = Decimal(0)
        var byCategory: [String: Decimal] = [:]

        for member in members {
            if member.amount < 0 {
                let magnitude = -member.amount
                spentTotal += magnitude
                byCategory[member.category, default: 0] += magnitude
            } else {
                refundedTotal += member.amount
            }
        }

        spent = spentTotal
        refunded = refundedTotal
        net = refundedTotal - spentTotal

        let timestamps = members.map(\.timestamp)
        startDate = timestamps.min()
        endDate = timestamps.max()

        if let first = startDate, let last = endDate {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: first),
                to: calendar.startOfDay(for: last)
            ).day ?? 0
            // Inclusive: a trip that starts and ends the same day lasted one day, not zero.
            dayCount = max(1, days + 1)
        } else {
            dayCount = 0
        }

        perDay = dayCount > 0 ? spentTotal / Decimal(dayCount) : 0

        categories = byCategory
            .map { CategorySpend(category: $0.key, amount: $0.value) }
            // Name breaks ties so the order is stable between renders.
            .sorted { ($0.amount, $1.category) > ($1.amount, $0.category) }
    }
}
