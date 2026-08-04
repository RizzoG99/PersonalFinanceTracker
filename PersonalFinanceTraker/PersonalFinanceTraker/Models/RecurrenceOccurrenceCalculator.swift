import Foundation

/// Pure calendar-anchored occurrence-date generator — no SwiftData, so month-end/leap-day
/// edge cases (the riskiest part of recurring transactions) can be tested without a model context.
enum RecurrenceOccurrenceCalculator {
    /// Every occurrence strictly after `since` (or from `startDate` itself when `since` is nil),
    /// up to and including `through`, clipped by `ruleEndDate` if set.
    ///
    /// Each occurrence is computed independently from `startDate` (not by repeatedly advancing
    /// the previous occurrence), so a clamped date — e.g. Jan 31 -> Feb 28 for a monthly rule —
    /// never becomes the new anchor day for the following month.
    static func occurrenceDates(
        frequency: RecurrenceFrequency,
        interval: Int,
        startDate: Date,
        ruleEndDate: Date?,
        since: Date?,
        through: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        guard interval > 0 else { return [] }
        let cutoff = ruleEndDate.map { min($0, through) } ?? through
        guard startDate <= cutoff else { return [] }

        var dates: [Date] = []
        var n = 0
        // Safety valve, not a user-facing limit: 10,000 weekly occurrences is ~190 years.
        while n < 10_000 {
            guard let occurrence = occurrenceDate(for: n, frequency: frequency, interval: interval, startDate: startDate, calendar: calendar) else { break }
            if occurrence > cutoff { break }
            if since == nil || occurrence > since! {
                dates.append(occurrence)
            }
            n += 1
        }
        return dates
    }

    private static func occurrenceDate(for n: Int, frequency: RecurrenceFrequency, interval: Int, startDate: Date, calendar: Calendar) -> Date? {
        switch frequency {
        case .weekly:
            return calendar.date(byAdding: .day, value: n * interval * 7, to: startDate)
        case .monthly:
            return addingClampedMonths(n * interval, to: startDate, calendar: calendar)
        case .yearly:
            return addingClampedMonths(n * interval * 12, to: startDate, calendar: calendar)
        }
    }

    /// Adds calendar months anchored to `startDate`'s day-of-month, clamping to the target
    /// month's last day when it's shorter (e.g. Jan 31 + 1 month -> Feb 28/29).
    private static func addingClampedMonths(_ months: Int, to date: Date, calendar: Calendar) -> Date {
        guard months != 0 else { return date }
        let day = calendar.component(.day, from: date)
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        var comps = calendar.dateComponents([.year, .month], from: date)
        comps.month = (comps.month ?? 1) + months
        guard let firstOfTargetMonth = calendar.date(from: comps) else { return date }
        let dayRange = calendar.range(of: .day, in: .month, for: firstOfTargetMonth) ?? (1..<29)

        var targetComps = calendar.dateComponents([.year, .month], from: firstOfTargetMonth)
        targetComps.day = min(day, dayRange.count)
        targetComps.hour = time.hour
        targetComps.minute = time.minute
        targetComps.second = time.second
        return calendar.date(from: targetComps) ?? date
    }
}
