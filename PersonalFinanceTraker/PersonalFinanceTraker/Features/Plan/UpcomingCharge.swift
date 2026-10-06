import Foundation

/// One occurrence of a recurring rule (money in or out) inside the financial calendar (#189).
/// ponytail: rules are the only source; V2 predictable expenses (#196) add an "estimated" flag here.
struct UpcomingCharge: Identifiable, Equatable {
    var id: String { "\(rule.id)-\(date.timeIntervalSince1970)" }
    let rule: RecurrenceRuleSnapshot
    let date: Date

    /// Every occurrence still to happen from `now` up to the end of day `days - 1` (today is day 0),
    /// soonest first. Income and goal contributions included; forecast-only rules too.
    static func timeline(rules: [RecurrenceRuleSnapshot], now: Date = .now, days: Int = 14, calendar: Calendar = .current) -> [UpcomingCharge] {
        let startOfToday = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: days, to: startOfToday),
              let through = calendar.date(byAdding: .second, value: -1, to: end) else { return [] }
        return rules.flatMap { rule in
            // Strictly after the last materialized/matched occurrence: anything up to the cursor is
            // already paid — it happened, it isn't coming. An auto-recorded rule's earlier-today
            // occurrence was materialized; a forecast-only one is unpaid until a payment matches
            // it (#188), so it stays on "Today" all day — its time is just the last payment's.
            let floor = rule.autoRecord ? now : startOfToday.addingTimeInterval(-1)
            let since = max(floor, rule.lastMaterializedDate ?? .distantPast)
            return RecurrenceOccurrenceCalculator.occurrenceDates(
                frequency: rule.frequency, interval: rule.interval, startDate: rule.startDate,
                ruleEndDate: rule.endDate, since: since, through: through, calendar: calendar
            ).map { UpcomingCharge(rule: rule, date: $0) }
        }
        .sorted { $0.date < $1.date }
    }

    /// Money in and out across `charges`, both positive, in the base currency.
    static func totals(_ charges: [UpcomingCharge], currency: CurrencyService = CurrencyService()) -> (inflow: Decimal, outflow: Decimal) {
        charges.reduce((Decimal.zero, Decimal.zero)) { sum, charge in
            let amount = currency.convertToBase(charge.rule.amount, from: charge.rule.currencyCode)
            return amount >= 0 ? (sum.0 + amount, sum.1) : (sum.0, sum.1 - amount)
        }
    }
}
