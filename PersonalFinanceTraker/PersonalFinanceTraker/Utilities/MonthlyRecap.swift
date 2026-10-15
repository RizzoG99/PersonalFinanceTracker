//
//  MonthlyRecap.swift
//  PersonalFinanceTraker
//

import Foundation

/// Insights' monthly recap (#193): "what changed compared to before?" for the pay cycle that
/// just closed, against the one before it. Every amount positive, in base currency.
struct MonthlyRecap: Equatable, Sendable {
    enum Line: Equatable, Sendable {
        /// `difference` is closed − previous spending; nil when too small to mention.
        case spending(difference: Decimal?, previousName: String)
        case savingsRate(from: Double, to: Double)
        case mostImproved(category: String, saved: Decimal)
        /// Change in monthly recurring costs: positive = up.
        case recurring(change: Decimal)
    }

    let cycleStart: Date
    /// End-exclusive: the start of the cycle running now.
    let cycleEnd: Date
    let name: String
    let spent: Decimal
    let income: Decimal
    /// Empty when there's no full earlier cycle to compare with: the card shows totals only.
    let lines: [Line]

    var saved: Decimal { income - spent }
    var savingsRate: Double? { income > 0 ? Double(truncating: (saved / income) as NSDecimalNumber) : nil }
    var hasComparison: Bool { !lines.isEmpty }

    private static let minCategoryChange: Decimal = 10
    private static let minSpendingChange: Decimal = 10
    private static let minSpendingRatio: Decimal = 0.03

    /// Nil when the closed cycle has nothing recorded.
    static func make(
        transactions: [TransactionSnapshot],
        rules: [RecurrenceRuleSnapshot],
        payCycleStartDay: Int,
        currencyService: CurrencyService,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> MonthlyRecap? {
        let currentStart = PayCycleService.financialMonthStart(for: now, startDay: payCycleStartDay, calendar: calendar)
        guard let closedStart = calendar.date(byAdding: .month, value: -1, to: currentStart),
              let previousStart = calendar.date(byAdding: .month, value: -1, to: closedStart) else { return nil }

        let closed = totals(transactions, from: closedStart, to: currentStart, currencyService: currencyService)
        guard closed.count > 0 else { return nil }
        let name = cycleName(start: closedStart, end: currentStart, calendar: calendar)

        // Same rule as Home's month card: an earlier cycle counts only if recording had started
        // by its first day, or a partial cycle would make this one look like a big jump.
        let firstRecorded = calendar.startOfDay(for: transactions.lazy.map(\.timestamp).min() ?? now)
        guard previousStart >= firstRecorded else {
            return MonthlyRecap(cycleStart: closedStart, cycleEnd: currentStart, name: name,
                                spent: closed.out, income: closed.income, lines: [])
        }
        let previous = totals(transactions, from: previousStart, to: closedStart, currencyService: currencyService)

        var lines: [Line] = []
        let difference = closed.out - previous.out
        let threshold = max(minSpendingChange, previous.out * minSpendingRatio)
        lines.append(.spending(
            difference: abs(difference) < threshold ? nil : difference,
            previousName: cycleName(start: previousStart, end: closedStart, calendar: calendar)
        ))

        if closed.income > 0, previous.income > 0 {
            let from = rate(previous), to = rate(closed)
            // Rounded the way the card shows them, so "from 24 % to 24 %" never appears.
            if (from * 100).rounded() != (to * 100).rounded() { lines.append(.savingsRate(from: from, to: to)) }
        }

        // A category gone to zero is the classic improvement, so missing counts as 0.
        var best: (category: String, saved: Decimal)?
        for (category, before) in previous.byCategory {
            let saved = before - (closed.byCategory[category] ?? 0)
            if saved >= minCategoryChange, saved > (best?.saved ?? 0) { best = (category, saved) }
        }
        if let best { lines.append(.mostImproved(category: best.category, saved: best.saved)) }

        let lastDay = { (end: Date) in calendar.date(byAdding: .day, value: -1, to: end) ?? end }
        let recurringNow = recurringMonthly(rules, transactions, on: lastDay(currentStart), currencyService: currencyService)
        let recurringBefore = recurringMonthly(rules, transactions, on: lastDay(closedStart), currencyService: currencyService)
        let change = recurringNow - recurringBefore
        if abs(change) >= 1 { lines.append(.recurring(change: change)) }

        return MonthlyRecap(cycleStart: closedStart, cycleEnd: currentStart, name: name,
                            spent: closed.out, income: closed.income, lines: lines)
    }

    /// "September": the month holding most of the cycle (its midpoint), so a 27 Aug – 26 Sep
    /// cycle reads as September. Shared by the card title and the notification.
    static func cycleName(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        return midpoint.formatted(.dateTime.month(.wide))
    }

    // MARK: - Pieces

    private struct Totals {
        var income = Decimal.zero, out = Decimal.zero, count = 0
        var byCategory: [String: Decimal] = [:]
    }

    /// Mirrors `CycleSummaryService.compute`: goal transfers are neither income nor spending,
    /// so they end up in `saved`.
    private static func totals(_ transactions: [TransactionSnapshot], from start: Date, to end: Date,
                               currencyService: CurrencyService) -> Totals {
        var totals = Totals()
        for tx in transactions where tx.timestamp >= start && tx.timestamp < end {
            totals.count += 1
            let amount = currencyService.convertToBase(tx.amount, from: tx.currencyCode)
            if amount > 0 { totals.income += amount; continue }
            guard amount < 0, tx.goalId == nil else { continue }
            totals.out -= amount
            // Same key as the Insights explorer (`PieChartDataService.groupingKey`).
            totals.byCategory[tx.category.isEmpty ? "Other" : tx.category, default: 0] -= amount
        }
        return totals
    }

    private static func rate(_ totals: Totals) -> Double {
        Double(truncating: ((totals.income - totals.out) / totals.income) as NSDecimalNumber)
    }

    /// Monthly cost of the expense rules running on `date`. A confirmed fixed expense starts at
    /// its *last* detected payment, so the earliest matching payment stands in for its real
    /// start — otherwise confirming Netflix would read as "recurring costs went up".
    /// ponytail: current amounts only, rules keep no amount history; price changes don't show.
    private static func recurringMonthly(_ rules: [RecurrenceRuleSnapshot], _ transactions: [TransactionSnapshot],
                                         on date: Date, currencyService: CurrencyService) -> Decimal {
        rules
            .filter { $0.amount < 0 && $0.goalId == nil && $0.isActive(asOf: date) }
            .filter { rule in
                let key = RecurrenceDetector.commitmentKey(goalId: nil, note: rule.note)
                // A nameless rule would match every nameless payment: keep its own start.
                guard !key.note.isEmpty else { return rule.startDate <= date }
                let firstPayment = transactions
                    .filter { $0.amount < 0 && $0.goalId == nil
                        && RecurrenceDetector.commitmentKey(goalId: nil, note: $0.note) == key
                        && RecurrenceDetector.isSameAmount($0.amount, rule.amount) }
                    .map(\.timestamp).min()
                return min(rule.startDate, firstPayment ?? rule.startDate) <= date
            }
            .reduce(Decimal(0)) { $0 + abs(currencyService.convertToBase($1.monthlyEquivalent, from: $1.currencyCode)) }
    }
}

extension RecurrenceRuleSnapshot {
    /// Mirrors `RecurrenceRule.isActive(asOf:)`: not stopped before `date`.
    func isActive(asOf date: Date) -> Bool {
        endDate.map { $0 >= date } ?? true
    }
}
