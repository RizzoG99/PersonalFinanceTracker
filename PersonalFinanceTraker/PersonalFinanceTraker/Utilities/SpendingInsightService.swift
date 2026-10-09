//
//  SpendingInsightService.swift
//  PersonalFinanceTraker
//

import Foundation

struct SpendingInsightService {
    let currencyService: CurrencyService

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
}
