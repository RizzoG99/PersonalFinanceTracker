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
        didSet { Task { await computeTimelineData() } }
    }
    var categoryTrends: [CategoryTrend] = []
    var habitObservations: [HabitObservation] = []
    var forecast: SpendingForecast?
    var goals: [GoalSnapshot] = []
    var averageIncome: Decimal = 0
    var averageExpenses: Decimal = 0
    var averageSavings: Decimal = 0
    var showingAddGoal = false
    var goalEditDraft: GoalInput?
    var goalEditId: UUID?
    var selectedGoal: GoalSnapshot?
    var scoreSnapshots: [HealthScoreSnapshotData] = []
    var ignoreSubscriptions: Bool = UserDefaults.standard.bool(forKey: "healthScore.ignoreSubscriptions") {
        didSet {
            UserDefaults.standard.set(ignoreSubscriptions, forKey: "healthScore.ignoreSubscriptions")
            Task { await computeHealthScore() }
        }
    }

    // MARK: - Dependencies
    let repo: any ITransactionRepository
    /// Set by the owning view; notifies the app that persisted data changed
    @ObservationIgnored var onDataChanged: (() -> Void)?
    @ObservationIgnored private let chartDataService = ChartDataService()
    @ObservationIgnored private let currencyService: CurrencyService
    @ObservationIgnored private let anomalyService = TimelineAnomalyService()
    @ObservationIgnored private let healthService: FinancialHealthService
    @ObservationIgnored private let forecastService: SpendingForecastService
    @ObservationIgnored private let averagesService: StatisticalAverageService
    @ObservationIgnored private let insightService: SpendingInsightService

    private var transactions: [TransactionSnapshot] = []
    private var expenseTransactions: [TransactionSnapshot] = []

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
        Task {
            await reloadData()
        }
    }

    /// Internal rather than private so tests can await the load directly. `load()`
    /// is fire-and-forget, which left tests with nothing to wait on but a fixed
    /// sleep — the cause of an intermittent failure in CompassViewModelTests.
    func reloadData() async {
        do {
            async let txs = repo.fetchAll()
            async let fetchedGoals = repo.fetchGoals()
            transactions = try await txs
            goals = (try? await fetchedGoals) ?? []
        } catch {
            print("CompassViewModel load error: \(error)")
            return
        }
        expenseTransactions = transactions.filter { $0.amount < 0 && $0.goalId == nil }
        // overlap the two repo-I/O computations with the pure ones; all run on MainActor, awaits interleave
        async let health: Void = computeHealthScore()
        async let futureForecast: Void = computeForecast()
        await computeHeroInsight()
        await computeTimelineData()
        await computeCategoryTrends()
        await computeHabits()
        calculateAverages()
        await health
        await futureForecast
    }

    // MARK: - Goal CRUD

    func beginEditingGoal(_ goal: GoalSnapshot) {
        goalEditId = goal.id
        goalEditDraft = GoalInput(
            name: goal.name,
            targetAmount: goal.targetAmount,
            deadline: goal.deadline,
            colorToken: goal.colorToken,
            iconName: goal.iconName
        )
    }

    func saveGoalEdits() {
        guard let id = goalEditId, let draft = goalEditDraft else { return }
        Task {
            try? await repo.updateGoal(id: id, with: draft)
            goalEditDraft = nil
            goalEditId = nil
            await reloadGoals()
        }
    }

    private func reloadGoals() async {
        goals = (try? await repo.fetchGoals()) ?? []
    }

    func addGoal(_ input: GoalInput) {
        Task {
            try? await repo.addGoal(input)
            await reloadGoals()
        }
    }

    func deleteGoal(_ goal: GoalSnapshot) {
        Task {
            try? await repo.deleteGoal(id: goal.id)
            goals.removeAll { $0.id == goal.id }
        }
    }

    func addFunds(amount: Decimal, to goal: GoalSnapshot) {
        Task {
            let input = TransactionInput(
                timestamp: Date(),
                amount: -amount,
                note: "",
                category: "→ \(goal.name)",
                currencyCode: "EUR",
                goalId: goal.id,
                categoryPersistentId: nil
            )
            try? await repo.add(input)
            onDataChanged?()
            await reloadData()
        }
    }

    // MARK: - Computations

    private func computeHeroInsight() async {
        heroInsight = insightService.heroInsight(expenseTransactions: expenseTransactions)
    }

    private func computeHealthScore() async {
        let budgetedCategories = (try? await repo.fetchCategories())?.filter { $0.monthlyBudget != nil } ?? []

        // ponytail: Require at least some income or expense in the 6-month window.
        // Could later be tightened (e.g., N transactions minimum) if all-zero turns out too lenient.
        let calendar = Calendar.current
        let now = Date.now
        let financialMonths = PayCycleService.financialMonths(count: 6, before: now, startDay: AppSettings.storedStartDay, calendar: calendar)
        let sixMonthsAgo = financialMonths.first?.start ?? calendar.date(byAdding: .month, value: -6, to: now) ?? now
        let hasRecentIncome = transactions.contains { $0.timestamp >= sixMonthsAgo && $0.amount > 0 }
        let hasRecentExpense = expenseTransactions.contains { $0.timestamp >= sixMonthsAgo }

        if !hasRecentIncome && !hasRecentExpense {
            healthScore = nil
        } else {
            healthScore = healthService.compute(
                transactions: transactions,
                expenseTransactions: expenseTransactions,
                budgetedCategories: budgetedCategories,
                payCycleStartDay: AppSettings.storedStartDay,
                ignoreSubscriptions: ignoreSubscriptions
            )
        }
        await saveSnapshotIfNeeded()
        scoreSnapshots = (try? await repo.fetchSnapshots(limit: 6)) ?? []
    }

    func computeTimelineData() async {
        let raw = chartDataService.generateChartData(from: expenseTransactions, for: selectedTimePeriod, payCycleStartDay: AppSettings.storedStartDay)
        timelineData = anomalyService.annotateWithSpikes(raw)
    }

    private func computeCategoryTrends() async {
        categoryTrends = insightService.categoryTrends(expenseTransactions: expenseTransactions)
    }

    private func computeHabits() async {
        habitObservations = insightService.habitObservations(expenseTransactions: expenseTransactions)
    }

    private func computeForecast() async {
        let cacheData = try? await repo.fetchForecastCache()
        let cacheState = cacheData.map {
            ForecastCacheState(
                monthKey: $0.monthKey,
                computedUpToDay: $0.computedUpToDay,
                days: $0.days,
                amounts: $0.amounts
            )
        }
        let (fc, updatedState) = forecastService.compute(
            expenseTransactions: expenseTransactions,
            cache: cacheState
        )
        let updatedCacheData = DailyForecastCacheData(
            monthKey: updatedState.monthKey,
            computedUpToDay: updatedState.computedUpToDay,
            days: updatedState.days,
            amounts: updatedState.amounts
        )
        try? await repo.saveForecastCache(updatedCacheData)
        forecast = fc
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

    private func saveSnapshotIfNeeded() async {
        guard let score = healthScore else { return }
        let existing = (try? await repo.fetchSnapshots(limit: 1)) ?? []
        let today = Calendar.current.startOfDay(for: Date.now)
        guard existing.first.map({ Calendar.current.startOfDay(for: $0.timestamp) }) != today else { return }

        let components = score.components
        let savingsScore = components.first(where: { $0.name == "Savings rate" })?.score ?? 0
        let stabilityScore = components.first(where: { $0.name == "Stability" })?.score ?? 0
        let adherenceScore = components.first(where: { $0.name == "Budget" })?.score ?? 0
        let subscriptionScore = ignoreSubscriptions ? 0 : (components.first(where: { $0.name == "Subscriptions" })?.score ?? 0)

        let snapshotData = HealthScoreSnapshotData(
            timestamp: Date.now,
            score: score.score,
            savingsScore: savingsScore,
            stabilityScore: stabilityScore,
            adherenceScore: adherenceScore,
            subscriptionScore: subscriptionScore
        )
        try? await repo.saveSnapshot(snapshotData)
    }

    // MARK: - Helpers

    func transferTotal(for goal: GoalSnapshot) -> Decimal {
        transactions
            .filter { $0.goalId == goal.id }
            .reduce(Decimal(0)) { $0 + abs(currencyService.convertToBase($1.amount, from: $1.currencyCode)) }
    }
}
