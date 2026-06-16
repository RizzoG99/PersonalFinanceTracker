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
        let topCats = categoryTotals.sorted { $0.value > $1.value }.prefix(3).map { $0.key }

        let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        var observations: [HabitObservation] = []

        for catName in topCats {
            let catTxns = recentExpenses.filter { $0.category == catName }
            guard catTxns.count >= 3 else { continue }

            var dayCounts: [Int: Int] = [:]
            for tx in catTxns {
                let weekday = calendar.component(.weekday, from: tx.timestamp)
                dayCounts[weekday, default: 0] += 1
            }
            guard let (peakDay, peakCount) = dayCounts.max(by: { $0.value < $1.value }),
                  peakCount >= 2 else { continue }

            let dayName = weekdayNames[peakDay - 1]
            let info = CategoryInfo.info(for: catName)
            let parts = catName.split(separator: " ", maxSplits: 1)
            let displayName = parts.count > 1 ? String(parts[1]) : catName

            observations.append(HabitObservation(
                sfSymbol: info.symbol,
                title: "\(displayName) peaks on \(dayName)s",
                detail: "\(peakCount) of \(catTxns.count) transactions this month"
            ))
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
