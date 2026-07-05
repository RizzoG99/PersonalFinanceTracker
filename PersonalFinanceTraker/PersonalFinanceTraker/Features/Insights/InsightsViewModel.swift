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
            computeHealthScore()
        }
    }

    // MARK: - Dependencies
    let repo: any ITransactionRepository
    @ObservationIgnored private let chartDataService = ChartDataService()
    @ObservationIgnored private let currencyService: CurrencyService
    @ObservationIgnored private let anomalyService = TimelineAnomalyService()
    @ObservationIgnored private let healthService: FinancialHealthService
    @ObservationIgnored private let forecastService: SpendingForecastService
    @ObservationIgnored private let averagesService: StatisticalAverageService
    @ObservationIgnored private let insightService: SpendingInsightService

    private var transactions: [TransactionSnapshot] = []
    private var expenseTransactions: [TransactionSnapshot] = []

    init(repo: any ITransactionRepository) {
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
            await fetchAndCompute()
        }
    }

    private func fetchAndCompute() async {
        do {
            transactions = try await repo.fetchAll()
            goals = (try? await repo.fetchGoals()) ?? []
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

    func addGoal(_ input: GoalInput) {
        Task {
            do {
                try await repo.addGoal(input)
                goals = (try? await repo.fetchGoals()) ?? goals
            } catch {
                print("Error adding goal: \(error)")
            }
        }
    }

    func saveGoalEdits() {
        guard let goalId = goalEditId, let draft = goalEditDraft else { return }
        Task {
            do {
                try await repo.updateGoal(id: goalId, with: draft)
                goals = (try? await repo.fetchGoals()) ?? goals
                goalEditId = nil
                goalEditDraft = nil
            } catch {
                print("Error updating goal: \(error)")
            }
        }
    }

    func deleteGoal(_ goal: GoalSnapshot) {
        Task {
            do {
                try await repo.deleteGoal(id: goal.id)
                goals.removeAll { $0.id == goal.id }
            } catch {
                print("Error deleting goal: \(error)")
            }
        }
    }

    func addFunds(amount: Decimal, to goal: GoalSnapshot) {
        Task {
            do {
                let input = TransactionInput(
                    timestamp: Date(),
                    amount: -amount,
                    note: "",
                    category: "→ \(goal.name)",
                    currencyCode: "EUR"
                )
                try await repo.add(input)
                await fetchAndCompute()
            } catch {
                print("Error adding funds: \(error)")
            }
        }
    }

    // MARK: - Computations

    private func computeHeroInsight() {
        heroInsight = insightService.heroInsight(expenseTransactions: expenseTransactions)
    }

    private func computeHealthScore() {
        Task {
            do {
                let categories = (try? await repo.fetchCategories()) ?? []
                let budgetedCategories = categories.filter { $0.monthlyBudget != nil }
                healthScore = healthService.compute(
                    transactions: transactions,
                    expenseTransactions: expenseTransactions,
                    budgetedCategories: budgetedCategories,
                    payCycleStartDay: AppSettings.storedStartDay,
                    ignoreSubscriptions: ignoreSubscriptions
                )
                saveSnapshotIfNeeded()
                scoreSnapshots = (try? await repo.fetchSnapshots(limit: 6)) ?? []
            } catch {
                print("Error computing health score: \(error)")
            }
        }
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
        Task {
            do {
                let cacheModel = try? await repo.fetchForecastCache()
                let cacheState = cacheModel.map {
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
                let updatedCacheModel = DailyForecastCacheData(
                    monthKey: updatedState.monthKey,
                    computedUpToDay: updatedState.computedUpToDay,
                    days: updatedState.days,
                    amounts: updatedState.amounts
                )
                try? await repo.saveForecastCache(updatedCacheModel)
                forecast = fc
            } catch {
                print("Error computing forecast: \(error)")
            }
        }
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
        Task {
            do {
                guard let score = healthScore else { return }
                let existing = (try? await repo.fetchSnapshots(limit: 1)) ?? []
                let today = Calendar.current.startOfDay(for: Date.now)
                guard existing.first.map({ Calendar.current.startOfDay(for: $0.timestamp) }) != today else { return }

                let components = score.components
                let savingsScore = components.first(where: { $0.name == "Savings rate" })?.score ?? 0
                let stabilityScore = components.first(where: { $0.name == "Stability" })?.score ?? 0
                let adherenceScore = components.first(where: { $0.name == "Budget" })?.score ?? 0
                let subscriptionScore = ignoreSubscriptions ? 0 : (components.first(where: { $0.name == "Subscriptions" })?.score ?? 0)

                let snapshot = HealthScoreSnapshotData(
                    timestamp: Date.now,
                    score: score.score,
                    savingsScore: savingsScore,
                    stabilityScore: stabilityScore,
                    adherenceScore: adherenceScore,
                    subscriptionScore: subscriptionScore
                )
                try? await repo.saveSnapshot(snapshot)
            } catch {
                print("Error saving snapshot: \(error)")
            }
        }
    }

    // MARK: - Helpers

    func transferTotal(for goal: GoalSnapshot) -> Decimal {
        transactions
            .filter { $0.goalId == goal.id }
            .reduce(Decimal(0)) { $0 + abs(currencyService.convertToBase($1.amount, from: $1.currencyCode)) }
    }
}
