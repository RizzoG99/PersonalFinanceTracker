import Foundation

struct FinancialHealthService {
    let currencyService: CurrencyService

    func compute(
        transactions: [TransactionModel],
        expenseTransactions: [TransactionModel],
        budgetedCategories: [CategoryModel],
        payCycleStartDay: Int = 1,
        ignoreSubscriptions: Bool = false
    ) -> HealthScore {
        let calendar = Calendar.current
        let now = Date.now
        let financialMonths = PayCycleService.financialMonths(count: 6, before: now, startDay: payCycleStartDay, calendar: calendar)
        let sixMonthsAgo = financialMonths.first?.start ?? calendar.date(byAdding: .month, value: -6, to: now) ?? now
        let recent = transactions.filter { $0.timestamp >= sixMonthsAgo }
        let recentExpenses = expenseTransactions.filter { $0.timestamp >= sixMonthsAgo }

        // 1. Savings rate (target: 20% → full score)
        let income = recent.filter { $0.amount > 0 }.reduce(Decimal(0)) {
            $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode)
        }
        let expenses = sumExpenses(recentExpenses)
        let savingsRate = income > 0
            ? Double(truncating: ((income - expenses) / income) as NSDecimalNumber)
            : 0
        let rawSavingsScore = max(0, min(25, Int((savingsRate / 0.20) * 25)))

        // 2. Spending stability via coefficient of variation
        let monthlyExpenses: [Double] = financialMonths.map { month in
            let total = expenseTransactions
                .filter { $0.timestamp >= month.start && $0.timestamp <= month.end }
                .reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) }
            return Double(truncating: abs(total) as NSDecimalNumber)
        }
        let mean = monthlyExpenses.reduce(0, +) / 6
        let variance = mean > 0
            ? monthlyExpenses.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / 6
            : 0
        let cov = mean > 0 ? variance.squareRoot() / mean : 0
        let rawStabilityScore = max(0, min(25, Int((1.0 - cov / 0.5) * 25)))

        // 3. Budget adherence (current financial month only)
        let currentFinancialMonth = PayCycleService.currentFinancialMonth(startDay: payCycleStartDay, calendar: calendar)
        let thisMonthExpenses = expenseTransactions.filter { $0.timestamp >= currentFinancialMonth.start && $0.timestamp <= currentFinancialMonth.end }
        let rawAdherenceScore: Int
        let adheringCount: Int
        if budgetedCategories.isEmpty {
            rawAdherenceScore = 25
            adheringCount = 0
        } else {
            let adhering = budgetedCategories.filter { cat in
                let spent = sumExpenses(thisMonthExpenses.filter {
                    $0.category.localizedCaseInsensitiveContains(cat.name)
                })
                return spent <= (cat.monthlyBudget ?? 0)
            }
            adheringCount = adhering.count
            rawAdherenceScore = Int(Double(adheringCount) / Double(budgetedCategories.count) * 25)
        }

        // 4. Subscription control (above 15% of expenses = 0 pts)
        let subscriptionExpenses = sumExpenses(recentExpenses.filter {
            $0.category.localizedCaseInsensitiveContains("subscri") ||
            $0.category.localizedCaseInsensitiveContains("stream")
        })
        let subRatio = expenses > 0
            ? Double(truncating: (subscriptionExpenses / expenses) as NSDecimalNumber)
            : 0
        let rawSubscriptionScore = max(0, min(25, Int(round((1.0 - subRatio / 0.15) * 25))))

        // Build components — redistribute subscription pts when opted out
        let components: [ScoreComponent]
        let total: Int

        if ignoreSubscriptions {
            // 100 pts split across 3 components: savings=34, stability=33, adherence=33
            let savingsScore  = min(34, Int(Double(rawSavingsScore)   / 25.0 * 34.0))
            let stabilityScore = min(33, Int(Double(rawStabilityScore) / 25.0 * 33.0))
            let adherenceScore = min(33, Int(Double(rawAdherenceScore) / 25.0 * 33.0))
            total = savingsScore + stabilityScore + adherenceScore
            components = [
                ScoreComponent(
                    name: "Savings rate", score: savingsScore, max: 34,
                    explanation: savingsExplanation(rate: savingsRate),
                    tip: savingsScore < 34 ? savingsTip(rate: savingsRate, income: income) : nil
                ),
                ScoreComponent(
                    name: "Stability", score: stabilityScore, max: 33,
                    explanation: stabilityExplanation(cov: cov),
                    tip: stabilityScore < 33 ? stabilityTip(cov: cov) : nil
                ),
                ScoreComponent(
                    name: "Budget", score: adherenceScore, max: 33,
                    explanation: adherenceExplanation(adhering: adheringCount, total: budgetedCategories.count),
                    tip: adherenceScore < 33 ? adherenceTip(adhering: adheringCount, total: budgetedCategories.count) : nil
                ),
            ]
        } else {
            total = rawSavingsScore + rawStabilityScore + rawAdherenceScore + rawSubscriptionScore
            components = [
                ScoreComponent(
                    name: "Savings rate", score: rawSavingsScore, max: 25,
                    explanation: savingsExplanation(rate: savingsRate),
                    tip: rawSavingsScore < 25 ? savingsTip(rate: savingsRate, income: income) : nil
                ),
                ScoreComponent(
                    name: "Stability", score: rawStabilityScore, max: 25,
                    explanation: stabilityExplanation(cov: cov),
                    tip: rawStabilityScore < 25 ? stabilityTip(cov: cov) : nil
                ),
                ScoreComponent(
                    name: "Budget", score: rawAdherenceScore, max: 25,
                    explanation: adherenceExplanation(adhering: adheringCount, total: budgetedCategories.count),
                    tip: rawAdherenceScore < 25 ? adherenceTip(adhering: adheringCount, total: budgetedCategories.count) : nil
                ),
                ScoreComponent(
                    name: "Subscriptions", score: rawSubscriptionScore, max: 25,
                    explanation: subscriptionExplanation(ratio: subRatio),
                    tip: rawSubscriptionScore < 25 ? subscriptionTip() : nil
                ),
            ]
        }

        let label: String
        switch total {
        case 80...100: label = "Excellent financial habits"
        case 60...79:  label = "Solid with room to grow"
        case 40...59:  label = "Making progress"
        default:       label = "Needs attention"
        }

        return HealthScore(score: total, label: label, components: components)
    }

    // MARK: - Explanation helpers

    private func savingsExplanation(rate: Double) -> String {
        "You saved \(Int(rate * 100))% of income over the last 6 months."
    }

    private func savingsTip(rate: Double, income: Decimal) -> String {
        let targetRate = Decimal(string: "0.20")!
        let currentRate = Decimal(string: String(format: "%.6f", rate)) ?? Decimal(0)
        let gap = max(Decimal(0), targetRate - currentRate)
        let needed = gap * (income / 6)
        let rounded = Int(truncating: needed as NSDecimalNumber)
        guard rounded >= 1 else {
            return "Increase your savings rate from \(Int(rate * 100))% toward 20% to score higher."
        }
        return "Save €\(rounded) more per month to reach the 20% target."
    }

    private func stabilityExplanation(cov: Double) -> String {
        "Your monthly spending varies by \(Int(cov * 100))%."
    }

    private func stabilityTip(cov: Double) -> String {
        let pct = Int(cov * 100)
        return "Your spending varies \(pct)% month-to-month. Aim for under 10% for a top score."
    }

    private func adherenceExplanation(adhering: Int, total: Int) -> String {
        guard total > 0 else { return "No budgets set — add them in Profile to track spending limits." }
        return "\(adhering) of \(total) budgeted categories are within limit this month."
    }

    private func adherenceTip(adhering: Int, total: Int) -> String {
        guard total > 0 else { return "Set monthly budgets in Profile to unlock this score." }
        let over = total - adhering
        return "Bring \(over) over-budget \(over == 1 ? "category" : "categories") within limit."
    }

    private func subscriptionExplanation(ratio: Double) -> String {
        let pct = Int(ratio * 100)
        guard pct > 0 else { return "No subscription spending detected in the last 6 months." }
        return "Subscriptions are \(pct)% of expenses over the last 6 months."
    }

    private func subscriptionTip() -> String {
        "Keep subscriptions under 15% of expenses to earn full points."
    }

    private func sumExpenses(_ items: [TransactionModel]) -> Decimal {
        abs(items.reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) })
    }
}
