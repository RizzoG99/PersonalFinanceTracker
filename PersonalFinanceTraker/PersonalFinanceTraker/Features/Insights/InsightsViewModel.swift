//
//  InsightsViewModel.swift
//  PersonalFinanceTraker
//

import Foundation
import Combine

@MainActor
final class CompassViewModel: ObservableObject {
    // MARK: - Published
    @Published var heroInsight: HeroInsight?
    @Published var healthScore: HealthScore?
    @Published var timelineData: [TimelineDataPoint] = []
    @Published var selectedTimePeriod: TimePeriod = .month
    @Published var categoryTrends: [CategoryTrend] = []
    @Published var habitObservations: [HabitObservation] = []
    @Published var forecast: SpendingForecast?
    @Published var goals: [GoalModel] = []
    @Published var averageIncome: Decimal = 0
    @Published var averageExpenses: Decimal = 0
    @Published var averageSavings: Decimal = 0
    @Published var showingAddGoal = false
    @Published var goalToEdit: GoalModel?

    // MARK: - Dependencies
    let repo: ITransactionRepository
    private let chartDataService = ChartDataService()
    private let pieDataService = PieChartDataService()
    private let currencyService = CurrencyService()
    private var cancellables = Set<AnyCancellable>()

    private var transactions: [TransactionModel] = []
    private var expenseTransactions: [TransactionModel] = []

    init(repo: ITransactionRepository) {
        self.repo = repo
        $selectedTimePeriod
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.computeTimelineData() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Load

    func load() {
        do {
            transactions = try repo.fetchAll()
            goals = (try? repo.fetchGoals()) ?? []
        } catch {
            print("CompassViewModel load error: \(error)")
            return
        }
        expenseTransactions = transactions.filter { $0.amount < 0 && $0.goalId == nil }
        computeHeroInsight()
        computeHealthScore()
        computeTimelineData()
        computeCategoryTrends()
        computeHabits()
        computeForecast()
        calculateAverages()
    }

    // MARK: - Goal CRUD

    func addGoal(_ goal: GoalModel) {
        try? repo.addGoal(goal)
        goals = (try? repo.fetchGoals()) ?? goals
    }

    func saveGoalEdits() {
        try? repo.updateGoal()
    }

    func deleteGoal(_ goal: GoalModel) {
        try? repo.deleteGoal(goal)
        goals.removeAll { $0.id == goal.id }
    }

    // MARK: - Computations

    private func computeHeroInsight() {
        let calendar = Calendar.current
        let now = Date.now
        let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfCurrentMonth) ?? now

        let currentTotal = sumExpenses(expenseTransactions.filter {
            $0.timestamp >= startOfCurrentMonth
        })
        let lastTotal = sumExpenses(expenseTransactions.filter {
            $0.timestamp >= startOfLastMonth && $0.timestamp < startOfCurrentMonth
        })

        guard lastTotal > 0 else {
            heroInsight = HeroInsight(
                title: "Building your picture",
                subtitle: "Keep logging to unlock insights",
                emoji: "📊",
                trendDirection: .flat
            )
            return
        }

        let changeDecimal = (currentTotal - lastTotal) / lastTotal * 100
        let change = Double(truncating: changeDecimal as NSDecimalNumber)
        let absChange = Int(abs(change))

        if change < -5 {
            heroInsight = HeroInsight(
                title: "Spending \(absChange)% less",
                subtitle: "You're under last month's pace",
                emoji: "🎉",
                trendDirection: .down
            )
        } else if change > 10 {
            heroInsight = HeroInsight(
                title: "Spending \(absChange)% more",
                subtitle: "Watch your pace this month",
                emoji: "⚡",
                trendDirection: .up
            )
        } else {
            heroInsight = HeroInsight(
                title: "On track this month",
                subtitle: "Spending similar to last month",
                emoji: "✨",
                trendDirection: .flat
            )
        }
    }

    private func computeHealthScore() {
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
            let total = expenseTransactions.filter { $0.timestamp >= start && $0.timestamp < end }
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
        let budgetedCategories = (try? repo.fetchCategories())?.filter { $0.monthlyBudget != nil } ?? []
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

        healthScore = HealthScore(
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

    func computeTimelineData() {
        let raw = chartDataService.generateChartData(from: expenseTransactions, for: selectedTimePeriod)
        let values = raw.map { Double(truncating: $0.expenses as NSDecimalNumber) }

        guard !values.isEmpty else { timelineData = []; return }

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        let threshold = mean + 1.5 * variance.squareRoot()

        timelineData = zip(raw, values).map { point, val in
            TimelineDataPoint(period: point.period, expenses: point.expenses, isSpike: val > threshold && val > 0)
        }
    }

    private func computeCategoryTrends() {
        let calendar = Calendar.current
        let now = Date.now
        let lastMonthRef = calendar.date(byAdding: .month, value: -1, to: now) ?? now

        let current = pieDataService.generatePieChartData(from: expenseTransactions, for: .expenses, timePeriod: .month)
        let last = pieDataService.generatePieChartData(
            from: expenseTransactions, for: .expenses, timePeriod: .month, referenceDate: lastMonthRef
        )
        let lastDict = Dictionary(last.map { ($0.category, $0.amount) }, uniquingKeysWith: { a, _ in a })

        categoryTrends = Array(current.prefix(6)).map { cat in
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

    private func computeHabits() {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date.now) ?? Date.now
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
            // Strip leading emoji from "🍕 Restaurants" style names
            let parts = catName.split(separator: " ", maxSplits: 1)
            let displayName = parts.count > 1 ? String(parts[1]) : catName

            observations.append(HabitObservation(
                sfSymbol: info.symbol,
                title: "\(displayName) peaks on \(dayName)s",
                detail: "\(peakCount) of \(catTxns.count) transactions this month"
            ))
        }

        // Subscription observation
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

        habitObservations = observations
    }

    private func computeForecast() {
        let calendar = Calendar.current
        let now = Date.now
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let daysElapsed = max(1, calendar.dateComponents([.day], from: startOfMonth, to: now).day ?? 1)
        let daysLeft = max(0, daysInMonth - daysElapsed)

        let currentMonthExpenses = sumExpenses(expenseTransactions.filter {
            $0.timestamp >= startOfMonth
        })
        let dailyPace = currentMonthExpenses / Decimal(daysElapsed)
        let projected = dailyPace * Decimal(daysInMonth)

        let threeMonthTotal = (1...3).reduce(Decimal(0)) { total, offset in
            let start = calendar.date(byAdding: .month, value: -offset, to: startOfMonth) ?? startOfMonth
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return total + sumExpenses(expenseTransactions.filter {
                $0.timestamp >= start && $0.timestamp < end
            })
        }
        let lastThreeMonthAvg = threeMonthTotal / 3

        forecast = SpendingForecast(
            projectedAmount: projected,
            dailyPace: dailyPace,
            lastThreeMonthAvg: lastThreeMonthAvg,
            daysLeft: daysLeft
        )
    }

    private func calculateAverages() {
        let calendar = Calendar.current
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: Date.now) ?? Date.now
        let recent = transactions.filter { $0.timestamp >= sixMonthsAgo }
        let recentExpenses = expenseTransactions.filter { $0.timestamp >= sixMonthsAgo }

        let totalIncome = recent.filter { $0.amount > 0 }.reduce(Decimal(0)) {
            $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode)
        }
        let totalExpenses = sumExpenses(recentExpenses)

        averageIncome = totalIncome / 6
        averageExpenses = totalExpenses / 6
        averageSavings = averageIncome - averageExpenses
    }

    // MARK: - Helpers

    private func sumExpenses(_ items: [TransactionModel]) -> Decimal {
        abs(items.reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) })
    }

    func transferTotal(for goal: GoalModel) -> Decimal {
        transactions
            .filter { $0.goalId == goal.id }
            .reduce(Decimal(0)) { $0 + abs(currencyService.convertToBase($1.amount, from: $1.currencyCode)) }
    }
}
