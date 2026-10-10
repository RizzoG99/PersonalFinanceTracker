//
//  InsightsViewModel.swift
//  PersonalFinanceTraker
//

import Foundation

@Observable @MainActor
final class CompassViewModel {
    // MARK: - State
    var healthScore: HealthScore?
    /// Set once here, never in `reloadData()`: the app reloads this model on every data change
    /// and every foreground, and resetting would throw someone who just edited a transaction
    /// from a drill-down back to the current month.
    var explorerPeriod: ExplorerPeriod = .current(.month) {
        didSet { refreshExplorer() }
    }
    var explorerType: PieChartDataType = .expenses {
        didSet { refreshExplorer() }
    }
    private(set) var explorer: ExplorerBreakdown = .empty
    var habitObservations: [HabitObservation] = []
    /// The pay cycle that just closed vs the one before (#193); nil until a cycle has closed.
    private(set) var monthlyRecap: MonthlyRecap?
    var goals: [GoalSnapshot] = []
    var averageIncome: Decimal = 0
    var averageExpenses: Decimal = 0
    var averageSavings: Decimal = 0
    var showingAddGoal = false
    var goalEditDraft: GoalInput?
    var goalEditId: UUID?
    var selectedGoal: GoalSnapshot?
    /// Owned here (not local @State on HealthScoreSection) so the regular-width detail pane
    /// (see CompassView/AdaptiveSplitView) and the compact-width sheet can both read it.
    var showingHealthScoreDetail = false
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
    @ObservationIgnored private let currencyService: CurrencyService
    @ObservationIgnored private let pieDataService = PieChartDataService()
    @ObservationIgnored private let healthService: FinancialHealthService
    @ObservationIgnored private let averagesService: StatisticalAverageService
    @ObservationIgnored private let insightService: SpendingInsightService

    private(set) var transactions: [TransactionSnapshot] = []
    /// Earliest recorded transaction — the explorer's ‹ stops at the period containing it.
    var firstTransactionDate: Date? { transactions.lazy.map(\.timestamp).min() }

    /// ‹ is offered only while the previous period still overlaps recorded history; before the
    /// first transaction every period is empty, so going there is a dead end.
    var canGoToPreviousPeriod: Bool {
        guard let first = firstTransactionDate else { return false }
        return explorerPeriod.previous().interval.end > first
    }
    private var categories: [CategorySnapshot] = []
    private var allRules: [RecurrenceRuleSnapshot] = []
    /// Active recurring transfers into goals — the "planned" pace of a goal projection (#192).
    private var goalRules: [RecurrenceRuleSnapshot] = []
    private var expenseTransactions: [TransactionSnapshot] = []

    init(repo: ITransactionRepository) {
        self.repo = repo
        let currency = CurrencyService()
        self.currencyService = currency
        self.healthService = FinancialHealthService(currencyService: currency)
        self.averagesService = StatisticalAverageService(currencyService: currency)
        self.insightService = SpendingInsightService(currencyService: currency)
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
            async let fetchedCategories = repo.fetchCategories()
            // All rules, stopped ones too: the recap needs what was running last cycle.
            async let fetchedRules = repo.fetchAllRecurrenceRules()
            transactions = try await txs
            goals = (try? await fetchedGoals) ?? []
            categories = (try? await fetchedCategories) ?? []
            allRules = (try? await fetchedRules) ?? []
        } catch {
            print("CompassViewModel load error: \(error)")
            return
        }
        let today = Calendar.current.startOfDay(for: .now)
        goalRules = allRules.filter { $0.goalId != nil && $0.isActive(asOf: today) }
        monthlyRecap = MonthlyRecap.make(
            transactions: transactions, rules: allRules,
            payCycleStartDay: AppSettings.storedStartDay, currencyService: currencyService
        )
        expenseTransactions = transactions.filter { $0.amount < 0 && $0.goalId == nil }
        // overlap the repo-I/O computation with the pure ones; all run on MainActor, awaits interleave
        async let health: Void = computeHealthScore()
        refreshExplorer()
        await computeHabits()
        calculateAverages()
        await health
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

    private func refreshExplorer() {
        explorer = ExplorerBreakdown(
            transactions: transactions,
            categories: categories,
            period: explorerPeriod,
            dataType: explorerType,
            service: pieDataService
        )
    }

    /// A category row's drill-down, through the same filter as the slice it came from, so the
    /// list always adds up to the row's amount. Derived live, so edits made from the list show.
    func transactions(inCategory category: String, interval: DateInterval, dataType: PieChartDataType) -> [TransactionSnapshot] {
        pieDataService.explorerItems(transactions, in: interval, dataType: dataType)
            .filter { pieDataService.groupingKey(for: $0) == category }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func computeHabits() async {
        habitObservations = insightService.habitObservations(expenseTransactions: expenseTransactions)
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

    func projection(for goal: GoalSnapshot) -> GoalProjection {
        let planned = goalRules
            .filter { $0.goalId == goal.id }
            .reduce(Decimal(0)) { $0 + abs(currencyService.convertToBase($1.monthlyEquivalent, from: $1.currencyCode)) }
        let transfers = transactions
            .filter { $0.goalId == goal.id }
            .map { (date: $0.timestamp, amount: currencyService.convertToBase($0.amount, from: $0.currencyCode)) }
        return GoalProjection.make(goal: goal, saved: transferTotal(for: goal), plannedMonthly: planned, transfers: transfers)
    }
}
