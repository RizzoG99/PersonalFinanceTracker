//
//  DashboardViewModel.swift
//  PersonalFinanceTraker
//

import Foundation
import SwiftData

struct AnomalyCallout: Equatable {
    let message: String
    let dismissKey: String
}

@Observable @MainActor
final class DashboardViewModel {
    var transactions: [TransactionSnapshot] = []
    /// Home's hero (#190); nil until the first load finishes.
    var safeToSpend: SafeToSpend? = nil
    /// Home's month card (#191); nil when the cycle has nothing recorded.
    var cycleSummary: CycleSummary? = nil
    /// iPad: the forecast detail is open in the shared inspector.
    var showingCycleForecast = false
    var recentTransactions: [TransactionSnapshot] = []
    var loadError: String? = nil
    var anomalyCallout: AnomalyCallout? = nil
    var nearLimitBudgets: [BudgetProgress] = []
    /// Home's slice of the financial calendar (#189): recurring money in and out in the next 7 days.
    var upcomingWeek: [UpcomingCharge] = []
    /// Every budgeted category this cycle — Plan shows the full list, Home only the at-risk ones.
    var budgetProgress: [BudgetProgress] = []
    var dailyLoggingStatus = DailyLoggingStatus(hasLoggedToday: false, todayCount: 0, currentStreakDays: 0)
    var dailyCheckInStatus = DailyCheckInStatus(state: .pending, currentStreakDays: 0)
    var quickTransactionTemplates: [QuickTransactionTemplate] = []
    var showsReminderPrompt = false
    var quickAddError: String? = nil

    private let repo: any ITransactionRepository
    private let currencyService = CurrencyService()
    private var isLoaded = false
    private var categories: [CategorySnapshot] = []
    private var activeRules: [RecurrenceRuleSnapshot] = []

    init(repo: any ITransactionRepository) {
        self.repo = repo
    }

    /// Handle to the in-flight fetch so tests (and callers) can await completion
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?

    /// Injectable so tests don't race on shared UserDefaults across parallel suites
    @ObservationIgnored var payCycleStartDay: () -> Int = { AppSettings.storedStartDay }
    @ObservationIgnored var bufferPercent: () -> Int = { AppSettings.storedBufferPercent }
    @ObservationIgnored var currentDate: () -> Date = { .now }
    @ObservationIgnored var noSpendDateKeys: () -> Set<String> = { DailyCheckInStore.noSpendDateKeys() }

    func load() {
        guard !isLoaded else { return }
        isLoaded = true  // ponytail: mark loaded before fetch; call reload() to retry after failure
        loadTask = Task {
            await fetchAndCompute()
        }
    }

    func reload() {
        isLoaded = false
        load()
    }

    private func fetchAndCompute() async {
        do {
            async let txs = repo.fetchAll()
            async let cats = repo.fetchCategories()
            async let rules = repo.fetchAllRecurrenceRules()
            async let active = repo.fetchActiveRecurrenceRules()
            transactions = try await txs
            categories = try await cats
            // A preview, not the screen's point: rules failing to load just hide it.
            upcomingWeek = UpcomingCharge.timeline(rules: (try? await rules) ?? [], now: currentDate(), days: 7)
            // Same source as the widget's snapshot, so Home and widget never disagree.
            activeRules = (try? await active) ?? []
            await calculateMetrics()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func optimisticRemove(ids: [PersistentIdentifier]) {
        transactions.removeAll { ids.contains($0.id) }
        Task { await calculateMetrics() }
    }

    private func calculateMetrics() async {
        let payCycleStartDay = payCycleStartDay()
        // ponytail: metrics computed off the MainActor from the already-fetched snapshots;
        // move aggregation into TransactionActor if the dataset ever makes the fetch itself the bottleneck
        let recent = await Task.detached(priority: .userInitiated) { [transactions] in
            Self.mostRecent(transactions)
        }.value

        recentTransactions = recent
        safeToSpend = SafeToSpendSnapshotBuilder.compute(
            transactions: transactions, activeRules: activeRules, payCycleStartDay: payCycleStartDay,
            bufferPercent: bufferPercent(), currencyService: currencyService, now: currentDate()
        )
        cycleSummary = CycleSummaryService.compute(
            transactions: transactions, payCycleStartDay: payCycleStartDay,
            currencyService: currencyService, now: currentDate()
        )
        // Rescheduled with every Home load (launch, data or pay-cycle change), like the reminder.
        ReminderService.shared.scheduleMonthlyRecap(cycleHasActivity: cycleSummary != nil)
        quickTransactionTemplates = HabitLoggingService.quickTemplates(from: transactions)
        refreshDailyCheckInState()
        anomalyCallout = Self.computeAnomalyCallout(
            transactions,
            payCycleStartDay: payCycleStartDay,
            dismissedKey: UserDefaults.standard.string(forKey: Self.dismissedAnomalyDefaultsKey)
        )
        budgetProgress = BudgetProgressService.computeProgress(
            categories: categories, transactions: transactions, payCycleStartDay: payCycleStartDay
        )
        nearLimitBudgets = BudgetProgressService.nearLimit(budgetProgress)
        showsReminderPrompt = Self.computeShowsReminderPrompt(
            transactions,
            remindersEnabled: UserDefaults.standard.bool(forKey: "reminderEnabled"),
            promptDismissed: UserDefaults.standard.bool(forKey: Self.dismissedReminderPromptDefaultsKey)
        )
    }

    private func refreshDailyCheckInState() {
        let now = currentDate()
        dailyLoggingStatus = HabitLoggingService.computeStatus(transactions: transactions, now: now)
        if dailyLoggingStatus.hasLoggedToday {
            DailyCheckInStore.undoNoSpend(for: now)
        }
        dailyCheckInStatus = DailyCheckInService.computeStatus(
            transactions: transactions,
            noSpendDateKeys: noSpendDateKeys(),
            now: now
        )
        HabitWidgetSnapshotStore.save(HabitWidgetSnapshotStore.makeSnapshot(
            status: dailyLoggingStatus,
            checkInStatus: dailyCheckInStatus,
            templates: quickTransactionTemplates,
            now: now
        ))
    }

    /// O(n) top-5, no full sort.
    nonisolated private static func mostRecent(_ transactions: [TransactionSnapshot]) -> [TransactionSnapshot] {
        var recent: [TransactionSnapshot] = []
        for tx in transactions where recent.count < 5 || tx.timestamp > (recent.last?.timestamp ?? .distantPast) {
            recent.append(tx)
            recent.sort { $0.timestamp > $1.timestamp }
            if recent.count > 5 { recent.removeLast() }
        }
        return recent
    }

    private static let dismissedAnomalyDefaultsKey = "dismissedAnomalyCalloutKey"
    private static let dismissedReminderPromptDefaultsKey = "dismissedDailyLoggingReminderPrompt"

    nonisolated static func computeNearLimitBudgets(
        _ transactions: [TransactionSnapshot],
        _ categories: [CategorySnapshot],
        payCycleStartDay: Int
    ) -> [BudgetProgress] {
        let progress = BudgetProgressService.computeProgress(
            categories: categories, transactions: transactions, payCycleStartDay: payCycleStartDay
        )
        return BudgetProgressService.nearLimit(progress)
    }

    nonisolated static func computeAnomalyCallout(
        _ transactions: [TransactionSnapshot],
        payCycleStartDay: Int,
        dismissedKey: String?
    ) -> AnomalyCallout? {
        let points = ChartDataService().generateChartData(
            from: transactions, for: .month, payCycleStartDay: payCycleStartDay
        )
        let annotated = TimelineAnomalyService().annotateWithSpikes(points)
        guard let spike = annotated.last(where: { $0.isSpike }) else { return nil }
        let (cycleStart, _) = PayCycleService.currentFinancialMonth(startDay: payCycleStartDay)
        let key = "\(cycleStart.timeIntervalSince1970)_\(spike.period)"
        guard key != dismissedKey else { return nil }
        let amount = Double(truncating: spike.expenses as NSDecimalNumber)
        let message = String(localized: "Unusually high spending in \(spike.period): \(amount.formatted(.currency(code: "EUR")))")
        return AnomalyCallout(message: message, dismissKey: key)
    }

    func dismissAnomaly() {
        if let key = anomalyCallout?.dismissKey {
            UserDefaults.standard.set(key, forKey: Self.dismissedAnomalyDefaultsKey)
        }
        anomalyCallout = nil
    }

    var hasNoTransactions: Bool {
        transactions.isEmpty
    }

    nonisolated static func computeShowsReminderPrompt(
        _ transactions: [TransactionSnapshot],
        remindersEnabled: Bool,
        promptDismissed: Bool
    ) -> Bool {
        HabitLoggingService.shouldShowReminderPrompt(
            transactions: transactions,
            remindersEnabled: remindersEnabled,
            promptDismissed: promptDismissed
        )
    }

    func dismissReminderPrompt() {
        UserDefaults.standard.set(true, forKey: Self.dismissedReminderPromptDefaultsKey)
        showsReminderPrompt = false
    }

    func markReminderPromptAccepted() {
        UserDefaults.standard.set(false, forKey: Self.dismissedReminderPromptDefaultsKey)
        UserDefaults.standard.set(true, forKey: "reminderEnabled")
        showsReminderPrompt = false
        ReminderService.shared.reschedule(hasCompletedToday: dailyCheckInStatus.isComplete)
    }

    func repeatTemplate(_ template: QuickTransactionTemplate) async -> Bool {
        do {
            let input = try QuickAddService.makeInput(
                amount: template.amountMagnitudeDouble,
                categoryName: template.category,
                isExpense: template.isExpense,
                note: template.note,
                categories: categories
            )
            try await repo.add(input)
            quickAddError = nil
            reload()
            ReminderService.shared.reschedule(hasCompletedToday: true)
            return true
        } catch {
            quickAddError = error.localizedDescription
            return false
        }
    }

    func completeNoSpendCheckIn() {
        guard !dailyLoggingStatus.hasLoggedToday else { return }
        DailyCheckInStore.confirmNoSpend(for: currentDate())
        refreshDailyCheckInState()
        ReminderService.shared.reschedule(hasCompletedToday: true)
    }

    func undoNoSpendCheckIn() {
        guard dailyCheckInStatus.state == .noSpendConfirmed else { return }
        DailyCheckInStore.undoNoSpend(for: currentDate())
        refreshDailyCheckInState()
        ReminderService.shared.reschedule(hasCompletedToday: false)
    }

}
