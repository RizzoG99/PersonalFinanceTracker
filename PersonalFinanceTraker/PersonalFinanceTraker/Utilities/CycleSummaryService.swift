//
//  CycleSummaryService.swift
//  PersonalFinanceTraker
//

import Foundation

/// Home's month card (#191): this pay cycle's in / out / saved, and whether spending runs
/// faster than usual. Every amount positive, in base currency.
struct CycleSummary: Equatable, Sendable {
    enum Pace: Equatable, Sendable { case building, onTrack, faster }
    /// Spent so far in one category, and the change against the usual at the same point
    /// (meaningless while `.building` — there's no usual yet).
    struct CategoryPace: Equatable, Sendable { let category: String; let spent: Decimal; let delta: Decimal }

    let income: Decimal
    /// Goal transfers excluded — money put towards a goal counts as saved, not spent.
    let out: Decimal
    /// `out` up to now: a future-dated transaction hasn't happened yet, so pace ignores it.
    let spentSoFar: Decimal
    let pace: Pace
    /// Average of up to 3 earlier cycles at the same elapsed point, and over their whole length.
    let usualSoFar: Decimal
    let usualFullCycle: Decimal
    /// Every category with spending so far this cycle, biggest first — the forecast detail's list.
    let categories: [CategoryPace]
    /// Cumulative spend per cycle day (1-based) up to today, for the forecast chart.
    let dailyCumulative: [Decimal]
    let cycleStart: Date
    let payday: Date

    var saved: Decimal { income - out }
    /// Assumes the rest of the cycle goes as usual — so the forecast sentence can never
    /// contradict the pace verdict, unlike a linear projection skewed by rent on day one.
    var projected: Decimal { spentSoFar + usualFullCycle - usualSoFar }

    /// Up to two categories driving a `.faster` pace, biggest increase first.
    var drivers: [CategoryPace] {
        guard pace == .faster else { return [] }
        return Array(categories.filter { $0.delta > 0 }.sorted { $0.delta > $1.delta }.prefix(2))
    }
}

enum CycleSummaryService {
    private static let minElapsedDays: TimeInterval = 7
    private static let fasterRatio: Decimal = 1.1
    private static let usualCycles = 3

    /// Nil when the cycle has no income and no spending — the card has nothing to say.
    static func compute(
        transactions: [TransactionSnapshot],
        payCycleStartDay: Int,
        currencyService: CurrencyService,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CycleSummary? {
        let cycleStart = PayCycleService.financialMonthStart(for: now, startDay: payCycleStartDay, calendar: calendar)
        let payday = calendar.date(byAdding: .month, value: 1, to: cycleStart) ?? cycleStart
        let elapsed = now.timeIntervalSince(cycleStart)

        // An earlier cycle counts only if recording had started by then: a partial first
        // cycle (or a gap before an old import) would drag "usual" towards zero.
        let firstRecorded = calendar.startOfDay(for: transactions.lazy.map(\.timestamp).min() ?? now)
        let previous: [(start: Date, end: Date)] = (1...usualCycles).compactMap { offset in
            guard let start = calendar.date(byAdding: .month, value: -offset, to: cycleStart),
                  start >= firstRecorded,
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            return (start, end)
        }

        var income = Decimal.zero, out = Decimal.zero, spentSoFar = Decimal.zero
        var usualSoFarTotal = Decimal.zero, usualFullTotal = Decimal.zero
        var currentByCategory: [String: Decimal] = [:], usualByCategory: [String: Decimal] = [:]
        let todayIndex = max(0, calendar.dateComponents([.day], from: cycleStart, to: now).day ?? 0)
        var daily = Array(repeating: Decimal.zero, count: todayIndex + 1)

        for tx in transactions {
            let amount = currencyService.convertToBase(tx.amount, from: tx.currencyCode)
            let time = tx.timestamp
            if time >= cycleStart && time < payday {
                if amount > 0 { income += amount; continue }
                guard amount < 0, tx.goalId == nil else { continue }
                out -= amount
                guard time < now else { continue }
                spentSoFar -= amount
                // Same key as the Insights explorer (`PieChartDataService.groupingKey`).
                currentByCategory[tx.category.isEmpty ? "Other" : tx.category, default: 0] -= amount
                let day = calendar.dateComponents([.day], from: cycleStart, to: time).day ?? 0
                daily[min(day, todayIndex)] -= amount
            } else if amount < 0, tx.goalId == nil,
                      let cycle = previous.first(where: { time >= $0.start && time < $0.end }) {
                usualFullTotal -= amount
                if time < cycle.start.addingTimeInterval(elapsed) {
                    usualSoFarTotal -= amount
                    usualByCategory[tx.category.isEmpty ? "Other" : tx.category, default: 0] -= amount
                }
            }
        }
        guard income > 0 || out > 0 else { return nil }

        let count = Decimal(previous.count)
        let usualSoFar = previous.isEmpty ? 0 : usualSoFarTotal / count
        let usualFullCycle = previous.isEmpty ? 0 : usualFullTotal / count

        let pace: CycleSummary.Pace
        if elapsed < minElapsedDays * 86_400 || usualSoFar <= 0 {
            pace = .building
        } else if spentSoFar > usualSoFar * fasterRatio {
            pace = .faster
        } else {
            pace = .onTrack
        }

        let categories = currentByCategory
            .map { CycleSummary.CategoryPace(
                category: $0.key, spent: $0.value,
                delta: previous.isEmpty ? 0 : $0.value - (usualByCategory[$0.key] ?? 0) / count
            ) }
            .sorted { $0.spent > $1.spent }

        var running = Decimal.zero
        let cumulative = daily.map { running += $0; return running }

        return CycleSummary(
            income: income, out: out, spentSoFar: spentSoFar, pace: pace,
            usualSoFar: usualSoFar, usualFullCycle: usualFullCycle, categories: categories,
            dailyCumulative: cumulative, cycleStart: cycleStart, payday: payday
        )
    }
}
