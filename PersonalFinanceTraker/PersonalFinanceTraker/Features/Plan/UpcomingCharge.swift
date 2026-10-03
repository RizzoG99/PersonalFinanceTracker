import Foundation

/// The next time a recurring expense rule will charge — one row of Plan's "Coming up" list.
struct UpcomingCharge: Identifiable, Equatable {
    var id: UUID { rule.id }
    let rule: RecurrenceRuleSnapshot
    let date: Date

    /// The soonest next charge of each active expense rule still to happen, soonest first.
    /// Income rules are left out: this list answers "what do I have to pay soon" (Q5).
    static func next(rules: [RecurrenceRuleSnapshot], now: Date = .now, limit: Int = 5, calendar: Calendar = .current) -> [UpcomingCharge] {
        // ponytail: a 2-year horizon covers every frequency the app offers (yearly, interval 1–2);
        // widen it if longer intervals become possible
        guard let horizon = calendar.date(byAdding: .year, value: 2, to: now) else { return [] }
        let charges: [UpcomingCharge] = rules.compactMap { rule in
            guard rule.amount < 0 else { return nil }
            // Strictly after `now`, and after the last materialized occurrence: anything up to
            // there has already been recorded as a transaction — it isn't coming, it happened.
            // That also drops a rule stopped today right after its only charge.
            let since = max(now, rule.lastMaterializedDate ?? .distantPast)
            let date = RecurrenceOccurrenceCalculator.occurrenceDates(
                frequency: rule.frequency,
                interval: rule.interval,
                startDate: rule.startDate,
                ruleEndDate: rule.endDate,
                since: since,
                through: horizon,
                calendar: calendar
            ).first
            return date.map { UpcomingCharge(rule: rule, date: $0) }
        }
        return Array(charges.sorted { $0.date < $1.date }.prefix(limit))
    }
}
