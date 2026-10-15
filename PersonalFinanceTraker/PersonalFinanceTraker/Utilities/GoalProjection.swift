//
//  GoalProjection.swift
//  PersonalFinanceTraker
//

import Foundation

/// "Am I reaching my goals?" (#192): when a goal gets reached at the current pace and, with a
/// deadline, what it takes per month. Amounts are base-currency and positive.
///
/// Months are counted as contribution months, current month included, so the ETA and the
/// required amount never disagree: on Oct 10 a Dec 31 deadline leaves 3 (Oct, Nov, Dec).
struct GoalProjection: Equatable {
    enum Source: Equatable {
        /// Recurring transfers linked to the goal — what the user decided to put in.
        case planned
        /// Average of the transfers actually made over the last 3 months.
        case recent
    }

    enum State: Equatable {
        case complete
        /// No deadline, saving at `monthlyPace`.
        case eta(Date)
        case onTrack(eta: Date, deadline: Date)
        /// Saving, but slower than `required` per month needs to hit `deadline`.
        case behind(required: Decimal, deadline: Date)
        /// Nothing going in. `required` and `deadline` are set when the goal has a future deadline.
        case needsContribution(required: Decimal?, deadline: Date?)
        /// Deadline gone, goal not reached; `eta` is nil when nothing is going in.
        case deadlinePassed(eta: Date?)
    }

    let monthlyPace: Decimal
    let source: Source
    let state: State

    static let recentWindowMonths = 3

    /// - Parameters:
    ///   - plannedMonthly: monthly equivalent of the goal's active recurring transfers (0 if none).
    ///   - transfers: every transfer to the goal, base currency, any sign.
    static func make(
        goal: GoalSnapshot,
        saved: Decimal,
        plannedMonthly: Decimal,
        transfers: [(date: Date, amount: Decimal)],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GoalProjection {
        let source: Source = plannedMonthly > 0 ? .planned : .recent
        let pace = plannedMonthly > 0
            ? plannedMonthly
            : recentPace(goal: goal, transfers: transfers, now: now, calendar: calendar)
        let remaining = goal.targetAmount - saved
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now

        func eta() -> Date? {
            guard pace > 0 else { return nil }
            return calendar.date(byAdding: .month, value: paymentsNeeded(remaining, pace) - 1, to: thisMonth)
        }

        let state: State
        if remaining <= 0 {
            state = .complete
        } else if let deadline = goal.deadline {
            if calendar.startOfDay(for: deadline) < calendar.startOfDay(for: now) {
                state = .deadlinePassed(eta: eta())
            } else {
                let monthsLeft = (calendar.dateComponents([.month], from: thisMonth, to: deadline).month ?? 0) + 1
                let required = roundedUp(remaining / Decimal(monthsLeft))
                if let eta = eta() {
                    state = paymentsNeeded(remaining, pace) <= monthsLeft
                        ? .onTrack(eta: eta, deadline: deadline)
                        : .behind(required: required, deadline: deadline)
                } else {
                    state = .needsContribution(required: required, deadline: deadline)
                }
            }
        } else if let eta = eta() {
            state = .eta(eta)
        } else {
            state = .needsContribution(required: nil, deadline: nil)
        }
        return GoalProjection(monthlyPace: pace, source: source, state: state)
    }

    /// Transfers in the last 3 months over the months the goal has actually had, so a goal
    /// started 4 weeks ago with €200 in reads €200/month, not €66.
    private static func recentPace(
        goal: GoalSnapshot,
        transfers: [(date: Date, amount: Decimal)],
        now: Date,
        calendar: Calendar
    ) -> Decimal {
        guard let windowStart = calendar.date(byAdding: .month, value: -recentWindowMonths, to: now) else { return 0 }
        let recent = transfers.filter { $0.date >= windowStart && $0.date <= now }
        let total = recent.reduce(Decimal(0)) { $0 + abs($1.amount) }
        guard total > 0 else { return 0 }
        let firstTransfer = transfers.map(\.date).min() ?? goal.createdAt
        let start = max(windowStart, min(goal.createdAt, firstTransfer))
        let days = calendar.dateComponents([.day], from: start, to: now).day ?? 0
        // ponytail: 30.44-day average month; exact enough for a whole-month ETA
        let months = min(Double(recentWindowMonths), max(1, Double(days) / 30.44))
        return total / Decimal(months)
    }

    private static func paymentsNeeded(_ remaining: Decimal, _ pace: Decimal) -> Int {
        Int(truncating: roundedUp(remaining / pace) as NSDecimalNumber)
    }

    /// Whole euros, up: "€310/month" should actually get there.
    private static func roundedUp(_ value: Decimal) -> Decimal {
        var input = value, result = Decimal()
        NSDecimalRound(&result, &input, 0, .up)
        return result
    }
}

extension RecurrenceRuleSnapshot {
    /// The rule's amount spread over one month (sign kept).
    var monthlyEquivalent: Decimal {
        guard interval > 0 else { return 0 }
        let interval = Decimal(interval)
        switch frequency {
        case .monthly: return amount / interval
        case .weekly: return amount * 52 / 12 / interval
        case .yearly: return amount / 12 / interval
        }
    }
}
