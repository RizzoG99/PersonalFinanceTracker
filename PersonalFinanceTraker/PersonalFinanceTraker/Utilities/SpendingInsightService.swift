//
//  SpendingInsightService.swift
//  PersonalFinanceTraker
//

import Foundation

struct SpendingInsightService {
    let currencyService: CurrencyService
    let pieDataService: PieChartDataService

    func heroInsight(expenseTransactions: [TransactionModel]) -> HeroInsight {
        let calendar = Calendar.current
        let now = Date.now
        let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfCurrentMonth) ?? now

        let currentTotal = sumExpenses(expenseTransactions.filter { $0.timestamp >= startOfCurrentMonth })
        let lastTotal = sumExpenses(expenseTransactions.filter {
            $0.timestamp >= startOfLastMonth && $0.timestamp < startOfCurrentMonth
        })

        guard lastTotal > 0 else {
            return HeroInsight(
                title: "Building your picture",
                subtitle: "Keep logging to unlock insights",
                emoji: "📊",
                trendDirection: .flat
            )
        }

        let changeDecimal = (currentTotal - lastTotal) / lastTotal * 100
        let change = Double(truncating: changeDecimal as NSDecimalNumber)
        let absChange = Int(abs(change))

        if change < -5 {
            return HeroInsight(
                title: "Spending \(absChange)% less",
                subtitle: "You're under last month's pace",
                emoji: "🎉",
                trendDirection: .down
            )
        } else if change > 10 {
            return HeroInsight(
                title: "Spending \(absChange)% more",
                subtitle: "Watch your pace this month",
                emoji: "⚡",
                trendDirection: .up
            )
        } else {
            return HeroInsight(
                title: "On track this month",
                subtitle: "Spending similar to last month",
                emoji: "✨",
                trendDirection: .flat
            )
        }
    }

    func categoryTrends(expenseTransactions: [TransactionModel]) -> [CategoryTrend] {
        let calendar = Calendar.current
        let lastMonthRef = calendar.date(byAdding: .month, value: -1, to: .now) ?? .now

        let current = pieDataService.generatePieChartData(from: expenseTransactions, for: .expenses, timePeriod: .month)
        let last = pieDataService.generatePieChartData(
            from: expenseTransactions, for: .expenses, timePeriod: .month, referenceDate: lastMonthRef
        )
        let lastDict = Dictionary(last.map { ($0.category, $0.amount) }, uniquingKeysWith: { a, _ in a })

        return Array(current.prefix(6)).map { cat in
            let prev = lastDict[cat.category] ?? 0
            let change: Double
            if prev > 0 {
                change = Double(truncating: ((cat.amount - prev) / prev * 100) as NSDecimalNumber)
            } else {
                change = cat.amount > 0 ? 100 : 0
            }
            let direction: TrendDirection = change > 5 ? .up : change < -5 ? .down : .flat
            return CategoryTrend(category: cat, changePercent: change, direction: direction)
        }
    }

    func habitObservations(expenseTransactions: [TransactionModel]) -> [HabitObservation] {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: .now) ?? .now
        let recentExpenses = expenseTransactions.filter { $0.timestamp >= thirtyDaysAgo }

        var categoryTotals: [String: Decimal] = [:]
        for tx in recentExpenses {
            let cat = tx.category.isEmpty ? "Other" : tx.category
            categoryTotals[cat, default: 0] += abs(currencyService.convertToBase(tx.amount, from: tx.currencyCode))
        }
        // ponytail: topCats used by streak detection added in next step
        let topCats = categoryTotals.sorted { $0.value > $1.value }.prefix(5).map { $0.key }
        _ = topCats

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
            if weekendAvg > 0 && weekdayAvg > 0 {
                let ratio = Double(truncating: (weekendAvg / weekdayAvg) as NSDecimalNumber)
                if ratio >= 1.3 {
                    let ratioStr = String(format: "%.1f", ratio)
                    observations.append(HabitObservation(
                        sfSymbol: "calendar.badge.clock",
                        title: "Weekend spending is \(ratioStr)× higher",
                        detail: "\(weekendAvg.formattedEURCompact()) avg/day on weekends vs \(weekdayAvg.formattedEURCompact()) on weekdays"
                    ))
                } else {
                    let inverseRatio = Double(truncating: (weekdayAvg / weekendAvg) as NSDecimalNumber)
                    if inverseRatio >= 1.3 {
                        let ratioStr = String(format: "%.1f", inverseRatio)
                        observations.append(HabitObservation(
                            sfSymbol: "briefcase",
                            title: "Weekdays are your heaviest spending days",
                            detail: "\(weekdayAvg.formattedEURCompact()) avg/day on weekdays vs \(weekendAvg.formattedEURCompact()) on weekends"
                        ))
                    }
                }
            }
        }

        let subCount = recentExpenses.filter {
            $0.category.localizedCaseInsensitiveContains("subscri") ||
            $0.category.localizedCaseInsensitiveContains("stream")
        }.count
        if subCount >= 2 {
            observations.append(HabitObservation(
                sfSymbol: "play.circle.fill",
                title: "\(subCount) subscription charges this month",
                detail: "Review recurring charges regularly"
            ))
        }

        return observations
    }

    private func sumExpenses(_ items: [TransactionModel]) -> Decimal {
        abs(items.reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) })
    }
}
