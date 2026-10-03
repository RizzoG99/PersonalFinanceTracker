import Foundation

/// Everything the Insights explorer shows for one period and one type (income or expenses).
/// Pure: built from snapshots, so it's testable without a model context.
struct ExplorerBreakdown {
    struct Bar: Identifiable {
        var id: Date { date }
        let date: Date
        let amount: Decimal
    }

    /// Category rows (pie slices + Δ), largest first.
    let trends: [CategoryTrend]
    let bars: [Bar]
    /// `.day` or `.month` — what one bar stands for.
    let barUnit: Calendar.Component
    let total: Decimal

    static let empty = ExplorerBreakdown(trends: [], bars: [], barUnit: .day, total: 0)

    init(trends: [CategoryTrend], bars: [Bar], barUnit: Calendar.Component, total: Decimal) {
        self.trends = trends
        self.bars = bars
        self.barUnit = barUnit
        self.total = total
    }

    init(
        transactions: [TransactionSnapshot],
        categories: [CategorySnapshot],
        period: ExplorerPeriod,
        dataType: PieChartDataType,
        now: Date = .now,
        calendar: Calendar = .current,
        service: PieChartDataService = PieChartDataService()
    ) {
        let slices = service.generatePieChartData(from: transactions, for: dataType, in: period.interval, categories: categories)

        // Δ compares pace, not totals: an in-progress period is cut at `now` (a materialized
        // recurring dated later this month hasn't happened yet, #154) and set against the same
        // elapsed stretch of the previous period. The rows still show the full-period amount.
        let paceEnd = max(period.interval.start, min(period.interval.end, now))
        let currentPace = service.generatePieChartData(
            from: transactions, for: dataType, in: DateInterval(start: period.interval.start, end: paceEnd)
        )
        let previous = service.generatePieChartData(
            from: transactions, for: dataType, in: period.comparisonInterval(now: now, calendar: calendar)
        )
        let paceTrends = Dictionary(
            CategoryTrend.compare(current: currentPace, previous: previous).map { ($0.category.category, $0) },
            uniquingKeysWith: { a, _ in a }
        )
        trends = slices.map { slice in
            let pace = paceTrends[slice.category]
            // A category whose only entries are still ahead of `now` has no pace yet: flat, not "new".
            return CategoryTrend(
                category: slice,
                changePercent: pace?.changePercent ?? 0,
                direction: pace?.direction ?? .flat,
                isNew: pace?.isNew ?? false
            )
        }
        total = slices.reduce(0) { $0 + $1.amount }

        let days = calendar.dateComponents([.day], from: period.interval.start, to: period.interval.end).day ?? 0
        // ponytail: 62 days ≈ two months of daily bars; past that a bar per day is unreadable
        let unit: Calendar.Component = period.granularity == .year || days > 62 ? .month : .day
        barUnit = unit
        let items = service.explorerItems(transactions, in: period.interval, dataType: dataType)
        let currency = CurrencyService()
        var sums: [Date: Decimal] = [:]
        for item in items {
            guard let bucket = calendar.dateInterval(of: unit, for: item.timestamp)?.start else { continue }
            sums[bucket, default: 0] += abs(currency.convertToBase(item.amount, from: item.currencyCode))
        }
        // Every bucket of the period, empty ones included, so the axis covers the whole period.
        var bars: [Bar] = []
        var cursor = calendar.dateInterval(of: unit, for: period.interval.start)?.start ?? period.interval.start
        while cursor < period.interval.end {
            bars.append(Bar(date: cursor, amount: sums[cursor] ?? 0))
            guard let next = calendar.date(byAdding: unit, value: 1, to: cursor) else { break }
            cursor = next
        }
        self.bars = bars
    }
}
