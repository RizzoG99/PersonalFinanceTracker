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
    var scoreSnapshots: [HealthScoreSnapshot] = []
    var ignoreSubscriptions: Bool = UserDefaults.standard.bool(forKey: "healthScore.ignoreSubscriptions") {
        didSet {
            UserDefaults.standard.set(ignoreSubscriptions, forKey: "healthScore.ignoreSubscriptions")
            computeHealthScore()
        }
    }

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
            budgetedCategories: budgetedCategories,
            payCycleStartDay: AppSettings.storedStartDay,
            ignoreSubscriptions: ignoreSubscriptions
        )
        saveSnapshotIfNeeded()
        scoreSnapshots = (try? repo.fetchSnapshots(limit: 6)) ?? []
    }

    func computeTimelineData() {
        let raw = chartDataService.generateChartData(from: expenseTransactions, for: selectedTimePeriod, payCycleStartDay: AppSettings.storedStartDay)
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

    private func saveSnapshotIfNeeded() {
        guard let score = healthScore else { return }
        let existing = (try? repo.fetchSnapshots(limit: 1)) ?? []
        let today = Calendar.current.startOfDay(for: Date.now)
        guard existing.first.map({ Calendar.current.startOfDay(for: $0.timestamp) }) != today else { return }

        let components = score.components
        let savingsScore = components.first(where: { $0.name == "Savings rate" })?.score ?? 0
        let stabilityScore = components.first(where: { $0.name == "Stability" })?.score ?? 0
        let adherenceScore = components.first(where: { $0.name == "Budget" })?.score ?? 0
        let subscriptionScore = ignoreSubscriptions ? 0 : (components.first(where: { $0.name == "Subscriptions" })?.score ?? 0)

        let snapshot = HealthScoreSnapshot(
            timestamp: Date.now,
            score: score.score,
            savingsScore: savingsScore,
            stabilityScore: stabilityScore,
            adherenceScore: adherenceScore,
            subscriptionScore: subscriptionScore
        )
        try? repo.saveSnapshot(snapshot)
    }

    // MARK: - Helpers

    func transferTotal(for goal: GoalModel) -> Decimal {
        transactions
            .filter { $0.goalId == goal.id }
            .reduce(Decimal(0)) { $0 + abs(currencyService.convertToBase($1.amount, from: $1.currencyCode)) }
    }
}
