//
//  InsightsViewModel.swift
//  PersonalFinanceTraker
//

import Foundation

@Observable @MainActor
final class CompassViewModel {
    // MARK: - State
    var heroInsight: HeroInsight?
    var healthScore: HealthScore?
    var timelineData: [TimelineDataPoint] = []
    var selectedTimePeriod: TimePeriod = .month {
        didSet { computeTimelineData() }
    }
    var categoryTrends: [CategoryTrend] = []
    var habitObservations: [HabitObservation] = []
    var forecast: SpendingForecast?
    var goals: [GoalModel] = []
    var averageIncome: Decimal = 0
    var averageExpenses: Decimal = 0
    var averageSavings: Decimal = 0
    var showingAddGoal = false
    var goalToEdit: GoalModel?
    var selectedGoal: GoalModel?

    // MARK: - Dependencies
    let repo: ITransactionRepository
    @ObservationIgnored private let chartDataService = ChartDataService()
    @ObservationIgnored private let currencyService: CurrencyService
    @ObservationIgnored private let anomalyService = TimelineAnomalyService()
    @ObservationIgnored private let healthService: FinancialHealthService
    @ObservationIgnored private let forecastService: SpendingForecastService
    @ObservationIgnored private let averagesService: StatisticalAverageService
    @ObservationIgnored private let insightService: SpendingInsightService

    private var transactions: [TransactionModel] = []
    private var expenseTransactions: [TransactionModel] = []

    init(repo: ITransactionRepository) {
        self.repo = repo
        let currency = CurrencyService()
        self.currencyService = currency
        self.healthService = FinancialHealthService(currencyService: currency)
        self.forecastService = SpendingForecastService(currencyService: currency)
        self.averagesService = StatisticalAverageService(currencyService: currency)
        self.insightService = SpendingInsightService(currencyService: currency, pieDataService: PieChartDataService())
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

    func addFunds(amount: Decimal, to goal: GoalModel) {
        let tx = TransactionModel(
            timestamp: Date(),
            amount: -amount,
            note: "",
            category: "→ \(goal.name)",
            currencyCode: "EUR",
            goalId: goal.id
        )
        try? repo.add(tx)
        load()
    }

    // MARK: - Computations

    private func computeHeroInsight() {
        heroInsight = insightService.heroInsight(expenseTransactions: expenseTransactions)
    }

    private func computeHealthScore() {
        let budgetedCategories = (try? repo.fetchCategories())?.filter { $0.monthlyBudget != nil } ?? []
        healthScore = healthService.compute(
            transactions: transactions,
            expenseTransactions: expenseTransactions,
            budgetedCategories: budgetedCategories
        )
    }

    func computeTimelineData() {
        let raw = chartDataService.generateChartData(from: expenseTransactions, for: selectedTimePeriod)
        timelineData = anomalyService.annotateWithSpikes(raw)
    }

    private func computeCategoryTrends() {
        categoryTrends = insightService.categoryTrends(expenseTransactions: expenseTransactions)
    }

    private func computeHabits() {
        habitObservations = insightService.habitObservations(expenseTransactions: expenseTransactions)
    }

    private func computeForecast() {
        forecast = forecastService.compute(expenseTransactions: expenseTransactions)
    }

    private func calculateAverages() {
        let (inc, exp, sav) = averagesService.calculate(
            transactions: transactions,
            expenseTransactions: expenseTransactions
        )
        averageIncome = inc
        averageExpenses = exp
        averageSavings = sav
    }

    // MARK: - Helpers

    func transferTotal(for goal: GoalModel) -> Decimal {
        transactions
            .filter { $0.goalId == goal.id }
            .reduce(Decimal(0)) { $0 + abs(currencyService.convertToBase($1.amount, from: $1.currencyCode)) }
    }
}
