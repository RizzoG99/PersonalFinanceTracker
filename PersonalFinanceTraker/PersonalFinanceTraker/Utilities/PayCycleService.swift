import Foundation

struct PayCycleService {
    /// Given a start day (1-28) and a reference date, returns the start of the
    /// financial month containing that date.
    ///
    /// Example: if startDay = 10 and today is Jan 15, returns Jan 10.
    /// If today is Jan 5, returns Dec 10.
    static func financialMonthStart(
        for date: Date,
        startDay: Int,
        calendar: Calendar = .current
    ) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let currentDay = components.day ?? 1

        if currentDay >= startDay {
            // Start day hasn't arrived yet in next month, so we're in current month
            var startComponents = components
            startComponents.day = startDay
            return calendar.date(from: startComponents) ?? date
        } else {
            // Start day has passed in current month, so we're in next financial period
            // Go back one month and set day to startDay
            guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: date) else {
                return date
            }
            let prevComponents = calendar.dateComponents([.year, .month], from: previousMonth)
            var startComponents = prevComponents
            startComponents.day = startDay
            return calendar.date(from: startComponents) ?? date
        }
    }

    /// Returns an array of (start, end) date pairs for the last `count` financial months
    /// ending with the month containing `referenceDate`.
    ///
    /// Example: count=6, referenceDate=Jan 15, startDay=10
    /// Returns: [(Aug 10, Sep 9), (Sep 10, Oct 9), ..., (Jan 10, Feb 9)]
    static func financialMonths(
        count: Int,
        before referenceDate: Date,
        startDay: Int,
        calendar: Calendar = .current
    ) -> [(start: Date, end: Date)] {
        var months: [(start: Date, end: Date)] = []
        var currentDate = referenceDate

        for _ in 0..<count {
            let start = financialMonthStart(for: currentDate, startDay: startDay, calendar: calendar)
            let end = cycleEnd(start: start, calendar: calendar)

            months.insert((start: start, end: end), at: 0)

            // Move to the previous financial month
            currentDate = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        }

        return months
    }

    /// Returns the start and end dates of the current financial month.
    static func currentFinancialMonth(
        startDay: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let start = financialMonthStart(for: now, startDay: startDay, calendar: calendar)
        return (start: start, end: cycleEnd(start: start, calendar: calendar))
    }

    /// The cycle's last instant: callers filter with `<= end` and format `end` as the last day.
    /// It used to be 00:00 of that day, which dropped the whole last day from budgets and the
    /// health score (#342; #154 hit the same in charts).
    /// ponytail: 1 ms before the next start, not a half-open range — fixes every `<= end` caller
    /// at once; switch to `< nextStart` if sub-millisecond timestamps ever matter.
    /// `startOfDay`: where DST skips midnight (e.g. Havana), a cycle can start at 01:00, and a
    /// month later that clock time would run the cycle into the next one's first hour.
    private static func cycleEnd(start: Date, calendar: Calendar) -> Date {
        let nextStart = calendar.startOfDay(for: calendar.date(byAdding: .month, value: 1, to: start) ?? start)
        return nextStart.addingTimeInterval(-0.001)
    }
}
