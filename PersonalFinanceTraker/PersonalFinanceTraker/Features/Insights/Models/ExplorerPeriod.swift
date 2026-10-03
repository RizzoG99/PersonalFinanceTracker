import Foundation

/// The Insights explorer's period: a calendar week / month / year, or a custom range, that the
/// ‹ › arrows step through. Calendar-based on purpose (#187) — unlike Health Score, which follows
/// the pay cycle — so "September" means Sep 1–30 whatever the user's payday.
struct ExplorerPeriod: Hashable {
    enum Granularity: String, CaseIterable, Identifiable {
        case week, month, year, custom
        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: String(localized: "Week")
            case .month: String(localized: "Month")
            case .year: String(localized: "Year")
            case .custom: String(localized: "Custom")
            }
        }
    }

    let granularity: Granularity
    /// End-exclusive: `end` is the first instant of the next period.
    let interval: DateInterval

    /// The calendar week / month / year containing `now`. `.custom` falls back to the current month.
    static func current(_ granularity: Granularity, now: Date = .now, calendar: Calendar = .current) -> ExplorerPeriod {
        let component: Calendar.Component = switch granularity {
        case .week: .weekOfYear
        case .year: .year
        case .month, .custom: .month
        }
        let interval = calendar.dateInterval(of: component, for: now) ?? DateInterval(start: now, duration: 0)
        return ExplorerPeriod(granularity: granularity == .custom ? .month : granularity, interval: interval)
    }

    /// Whole days from `from`'s day through `through`'s day, both included.
    static func custom(from: Date, through: Date, calendar: Calendar = .current) -> ExplorerPeriod {
        let start = calendar.startOfDay(for: min(from, through))
        let lastDay = calendar.startOfDay(for: max(from, through))
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        return ExplorerPeriod(granularity: .custom, interval: DateInterval(start: start, end: end))
    }

    func previous(calendar: Calendar = .current) -> ExplorerPeriod { shifted(by: -1, calendar: calendar) }
    func next(calendar: Calendar = .current) -> ExplorerPeriod { shifted(by: 1, calendar: calendar) }

    /// True while `now` is inside the period — `›` is disabled then (no future periods).
    func isCurrent(now: Date = .now) -> Bool { interval.end > now }

    /// What the Δ column compares against. A finished period compares with the whole previous
    /// one; an in-progress period only with the same elapsed stretch of the previous one, so
    /// day 10 of this month isn't measured against a full month (#154). Clamped to the previous
    /// period's end: on Mar 31 the elapsed 30 days would otherwise spill past February.
    func comparisonInterval(now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let prev = previous(calendar: calendar).interval
        guard interval.contains(now) else { return prev }
        let elapsed = now.timeIntervalSince(interval.start)
        return DateInterval(start: prev.start, end: min(prev.end, prev.start.addingTimeInterval(elapsed)))
    }

    var label: String {
        switch granularity {
        case .month:
            return interval.start.formatted(.dateTime.month(.abbreviated).year())
        case .year:
            return interval.start.formatted(.dateTime.year())
        case .week, .custom:
            // end is exclusive; show the last included day
            let last = interval.end.addingTimeInterval(-1)
            return (interval.start..<last).formatted(.interval.day().month(.abbreviated).year())
        }
    }

    private func shifted(by value: Int, calendar: Calendar) -> ExplorerPeriod {
        switch granularity {
        case .custom:
            let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1
            let start = calendar.date(byAdding: .day, value: value * days, to: interval.start) ?? interval.start
            let end = calendar.date(byAdding: .day, value: days, to: start) ?? start
            return ExplorerPeriod(granularity: .custom, interval: DateInterval(start: start, end: end))
        case .week, .month, .year:
            let component: Calendar.Component = granularity == .week ? .weekOfYear : granularity == .month ? .month : .year
            let anchor = calendar.date(byAdding: component, value: value, to: interval.start) ?? interval.start
            return ExplorerPeriod.current(granularity, now: anchor, calendar: calendar)
        }
    }
}
