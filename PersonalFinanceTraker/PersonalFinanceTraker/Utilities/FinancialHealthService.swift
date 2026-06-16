//
//  FinancialHealthService.swift
//  PersonalFinanceTraker
//

import Foundation

struct FinancialHealthService {
    let currencyService: CurrencyService

    func compute(
        transactions: [TransactionModel],
        expenseTransactions: [TransactionModel],
        budgetedCategories: [CategoryModel]
    ) -> HealthScore {
        let calendar = Calendar.current
        let now = Date.now
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
        let recent = transactions.filter { $0.timestamp >= sixMonthsAgo }
        let recentExpenses = expenseTransactions.filter { $0.timestamp >= sixMonthsAgo }

        // 1. Savings rate (25 pts — 20% savings rate = full score)
        let income = recent.filter { $0.amount > 0 }.reduce(Decimal(0)) {
            $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode)
        }
        let expenses = sumExpenses(recentExpenses)
        let savingsRate = income > 0
            ? Double(truncating: ((income - expenses) / income) as NSDecimalNumber)
            : 0
        let savingsScore = max(0, min(25, Int((savingsRate / 0.20) * 25)))

        // 2. Spending stability via coefficient of variation (25 pts)
        let monthlyExpenses: [Double] = (0..<6).map { offset in
            let start = calendar.date(byAdding: .month, value: -offset, to: now) ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            let total = expenseTransactions
                .filter { $0.timestamp >= start && $0.timestamp < end }
                .reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) }
            return Double(truncating: abs(total) as NSDecimalNumber)
        }
        let mean = monthlyExpenses.reduce(0, +) / 6
        let variance = mean > 0
            ? monthlyExpenses.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / 6
            : 0
        let cov = mean > 0 ? variance.squareRoot() / mean : 0
        let stabilityScore = max(0, min(25, Int((1.0 - cov / 0.5) * 25)))

        // 3. Budget adherence (25 pts)
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let thisMonthExpenses = expenseTransactions.filter { $0.timestamp >= startOfMonth }
        let adherenceScore: Int
        if budgetedCategories.isEmpty {
            adherenceScore = 15
        } else {
            let adheringCount = budgetedCategories.filter { cat in
                let spent = sumExpenses(thisMonthExpenses.filter {
                    $0.category.localizedCaseInsensitiveContains(cat.name)
                })
                return spent <= (cat.monthlyBudget ?? 0)
            }.count
            adherenceScore = Int(Double(adheringCount) / Double(budgetedCategories.count) * 25)
        }

        // 4. Subscription control (25 pts — above 15% of expenses = 0 pts)
        let subscriptionExpenses = sumExpenses(recentExpenses.filter {
            $0.category.localizedCaseInsensitiveContains("subscri") ||
            $0.category.localizedCaseInsensitiveContains("stream")
        })
        let subRatio = expenses > 0
            ? Double(truncating: (subscriptionExpenses / expenses) as NSDecimalNumber)
            : 0
        let subscriptionScore = max(0, min(25, Int((1.0 - subRatio / 0.15) * 25)))

        let total = savingsScore + stabilityScore + adherenceScore + subscriptionScore
        let label: String
        switch total {
        case 80...100: label = "Excellent financial habits"
        case 60...79:  label = "Solid with room to grow"
        case 40...59:  label = "Making progress"
        default:       label = "Needs attention"
        }

        return HealthScore(
            score: total,
            label: label,
            components: [
                ScoreComponent(name: "Savings rate",  score: savingsScore,      max: 25),
                ScoreComponent(name: "Stability",     score: stabilityScore,    max: 25),
                ScoreComponent(name: "Budget",        score: adherenceScore,    max: 25),
                ScoreComponent(name: "Subscriptions", score: subscriptionScore, max: 25),
            ]
        )
    }

    private func sumExpenses(_ items: [TransactionModel]) -> Decimal {
        abs(items.reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) })
    }
}
