//
//  SpendingInsightService.swift
//  PersonalFinanceTraker
//

import Foundation

struct SpendingInsightService {
    let currencyService: CurrencyService
    let pieDataService: PieChartDataService

    // ponytail: elapsed-day threshold below which "% change" is noise (one transaction can
    // swing it wildly) rather than signal — raise it if early-month reports keep looking wrong.
    private static let minElapsedDaysForPaceComparison = 7

    func heroInsight(expenseTransactions: [TransactionSnapshot], payCycleStartDay startDay: Int = 1, referenceDate: Date = .now) -> HeroInsight {
        let calendar = Calendar.current
        let now = referenceDate
        // Pay-cycle-aware, like categoryTrends — otherwise this and Category Trends can silently
        // disagree about what "this month" means for anyone with a non-default cycle start day.
        let startOfCurrentMonth = PayCycleService.financialMonthStart(for: now, startDay: startDay, calendar: calendar)
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfCurrentMonth) ?? now

        // #154: comparing "so far this month" against a *complete* last month guarantees a false
        // "spending less" reading for ~80% of every month — cap last month at the same elapsed
        // span so the two totals cover the same number of days.
        let elapsed = now.timeIntervalSince(startOfCurrentMonth)
        let lastMonthCutoff = startOfLastMonth.addingTimeInterval(elapsed)

        // Also cap `currentTotal` at `now` — a future-dated transaction (a materialized recurring
        // rule later this month) would otherwise widen this side only, reintroducing the same
        // asymmetric-window bias in the opposite direction.
        let currentTotal = sumExpenses(expenseTransactions.filter { $0.timestamp >= startOfCurrentMonth && $0.timestamp < now })
        let lastTotal = sumExpenses(expenseTransactions.filter {
            $0.timestamp >= startOfLastMonth && $0.timestamp < lastMonthCutoff
        })

        guard lastTotal > 0 else {
            return HeroInsight(
                title: String(localized: "Building your picture"),
                subtitle: String(localized: "Keep logging to unlock insights"),
                trendDirection: .flat
            )
        }

        // Too little of the month has elapsed to say anything about pace — reuse the "not enough
        // history" copy rather than "similar to last month", which is a claim this branch
        // explicitly hasn't evaluated.
        let elapsedDays = elapsed / 86400
        guard elapsedDays >= Double(Self.minElapsedDaysForPaceComparison) else {
            return HeroInsight(
                title: String(localized: "Building your picture"),
                subtitle: String(localized: "Keep logging to unlock insights"),
                trendDirection: .flat
            )
        }

        let changeDecimal = (currentTotal - lastTotal) / lastTotal * 100
        let change = Double(truncating: changeDecimal as NSDecimalNumber)
        let absChange = Int(abs(change))

        if change < -5 {
            return HeroInsight(
                title: String(localized: "Spending \(absChange)% less"),
                subtitle: String(localized: "You're under last month's pace"),
                trendDirection: .down
            )
        } else if change > 10 {
            return HeroInsight(
                title: String(localized: "Spending \(absChange)% more"),
                subtitle: String(localized: "Watch your pace this month"),
                trendDirection: .up
            )
        } else {
            return HeroInsight(
                title: String(localized: "On track this month"),
                subtitle: String(localized: "Spending similar to last month"),
                trendDirection: .flat
            )
        }
    }

    func categoryTrends(expenseTransactions: [TransactionSnapshot], payCycleStartDay startDay: Int = 1, referenceDate: Date = .now) -> [CategoryTrend] {
        let calendar = Calendar.current
        let lastMonthRef = calendar.date(byAdding: .month, value: -1, to: referenceDate) ?? referenceDate

        // #154: same partial-vs-full bias as heroInsight — cap last month's window at how far
        // into the current financial month we are, so both pies cover the same span of days.
        let startOfCurrentMonth = PayCycleService.financialMonthStart(for: referenceDate, startDay: startDay, calendar: calendar)
        let elapsed = referenceDate.timeIntervalSince(startOfCurrentMonth)
        let startOfLastMonth = PayCycleService.financialMonthStart(for: lastMonthRef, startDay: startDay, calendar: calendar)
        let lastMonthCutoff = startOfLastMonth.addingTimeInterval(elapsed)

        let current = pieDataService.generatePieChartData(
            from: expenseTransactions, for: .expenses, timePeriod: .month, referenceDate: referenceDate, payCycleStartDay: startDay, upTo: referenceDate
        )
        let last = pieDataService.generatePieChartData(
            from: expenseTransactions, for: .expenses, timePeriod: .month, referenceDate: lastMonthRef, payCycleStartDay: startDay, upTo: lastMonthCutoff
        )
        let lastDict = Dictionary(last.map { ($0.category, $0.amount) }, uniquingKeysWith: { a, _ in a })

        return Array(current.prefix(6)).map { cat in
            let prev = lastDict[cat.category] ?? 0
            let isNew = prev == 0 && cat.amount > 0
            let change: Double
            if prev > 0 {
                change = Double(truncating: ((cat.amount - prev) / prev * 100) as NSDecimalNumber)
            } else {
                change = cat.amount > 0 ? 100 : 0
            }
            let direction: TrendDirection = change > 5 ? .up : change < -5 ? .down : .flat
            return CategoryTrend(category: cat, changePercent: change, direction: direction, isNew: isNew)
        }
    }

    func habitObservations(expenseTransactions: [TransactionSnapshot]) -> [HabitObservation] {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: .now) ?? .now
        let recentExpenses = expenseTransactions.filter { $0.timestamp >= thirtyDaysAgo }

        var categoryTotals: [String: Decimal] = [:]
        for tx in recentExpenses {
            let cat = tx.category.isEmpty ? "Other" : tx.category
            categoryTotals[cat, default: 0] += abs(currencyService.convertToBase(tx.amount, from: tx.currencyCode))
        }
        let topCats = categoryTotals.sorted { $0.value > $1.value }.prefix(5).map { $0.key }

        var observations: [HabitObservation] = []

        // MARK: - Weekend vs Weekday
        let weekendWeekdays: Set<Int> = [1, 7] // Sun=1, Sat=7
        if recentExpenses.count >= 5 {
            var weekendTotal = Decimal(0)
            var weekdayTotal = Decimal(0)
            for tx in recentExpenses {
                let converted = abs(currencyService.convertToBase(tx.amount, from: tx.currencyCode))
                if weekendWeekdays.contains(calendar.component(.weekday, from: tx.timestamp)) {
                    weekendTotal += converted
                } else {
                    weekdayTotal += converted
                }
            }
            // Fixed denominators: 30-day window always has ~10 weekend days and ~20 weekday days
            let weekendAvg = weekendTotal / 10
            let weekdayAvg = weekdayTotal / 20
            // ponytail: floor on the higher average, not the delta, so a real "spends more on X" pattern
            // still surfaces even when the gap is modest (weekdayHeavySpending's delta is only €7.5)
            let dailySpendFloor: Decimal = 10
            if weekendAvg > 0 && weekdayAvg > 0 && max(weekendAvg, weekdayAvg) >= dailySpendFloor {
                // ponytail: truncating is standard Decimal→Double in this codebase (see heroInsight, categoryTrends)
                let ratio = Double(truncating: (weekendAvg / weekdayAvg) as NSDecimalNumber)
                if ratio >= 1.3 {
                    let ratioStr = String(format: "%.1f", ratio)
                    observations.append(HabitObservation(
                        sfSymbol: "calendar.badge.clock",
                        title: String(localized: "Weekend spending is \(ratioStr)× higher"),
                        detail: String(localized: "\(weekendAvg.formattedEURCompact()) avg/day on weekends vs \(weekdayAvg.formattedEURCompact()) on weekdays")
                    ))
                } else {
                    let inverseRatio = Double(truncating: (weekdayAvg / weekendAvg) as NSDecimalNumber)
                    if inverseRatio >= 1.3 {
                        observations.append(HabitObservation(
                            sfSymbol: "briefcase",
                            title: String(localized: "Weekdays are your heaviest spending days"),
                            detail: String(localized: "\(weekdayAvg.formattedEURCompact()) avg/day on weekdays vs \(weekendAvg.formattedEURCompact()) on weekends")
                        ))
                    }
                }
            }
        }

        // MARK: - Category Streaks
        let startOfThisWeek: Date = {
            var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
            comps.weekday = 2 // Monday
            return calendar.date(from: comps) ?? .now
        }()

        var streakObservations: [(streak: Int, obs: HabitObservation)] = []
        for catName in topCats {
            let catTxns = recentExpenses.filter { $0.category == catName }
            guard catTxns.count >= 3 else { continue }

            var streak = 0
            for weekOffset in 0..<6 { // cap lookback at 6 weeks to keep streak counts readable
                guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: startOfThisWeek),
                      let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
                let hasTransaction = catTxns.contains { $0.timestamp >= weekStart && $0.timestamp < weekEnd }
                if hasTransaction { streak += 1 } else { break }
            }
            guard streak >= 3 else { continue }

            let info = CategoryInfo.info(for: catName)
            let parts = catName.split(separator: " ", maxSplits: 1)
            let displayName = parts.count > 1 ? String(parts[1]).localizedCategoryDisplay : catName.localizedCategoryDisplay
            // ponytail: "week"/"weeks" plural handled by the catalog's plural variation, not a hand-rolled ternary — see Localizable.xcstrings
            let detail = streak >= 4
                ? String(localized: "Every week for over a month")
                : String(localized: "Every week for \(streak) week")

            streakObservations.append((streak, HabitObservation(
                sfSymbol: info.symbol,
                title: String(localized: "\(displayName) — \(streak)-week streak"),
                detail: detail
            )))
        }
        observations += streakObservations.sorted { $0.streak > $1.streak }.prefix(2).map(\.obs)

        let subCount = recentExpenses.filter {
            $0.category.localizedCaseInsensitiveContains("subscri") ||
            $0.category.localizedCaseInsensitiveContains("stream")
        }.count
        if subCount >= 2 {
            observations.append(HabitObservation(
                sfSymbol: "play.circle.fill",
                // ponytail: "charge"/"charges" plural handled by the catalog's plural variation
                title: String(localized: "\(subCount) subscription charge this month"),
                detail: String(localized: "Review recurring charges regularly")
            ))
        }

        return observations
    }

    private func sumExpenses(_ items: [TransactionSnapshot]) -> Decimal {
        abs(items.reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) })
    }
}
