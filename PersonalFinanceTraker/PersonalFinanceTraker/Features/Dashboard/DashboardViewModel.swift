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
    var totalBalance: Decimal = 0
    var monthlyIncome: Decimal = 0
    var monthlyExpenses: Decimal = 0
    var recentTransactions: [TransactionSnapshot] = []
    var loadError: String? = nil
    var anomalyCallout: AnomalyCallout? = nil
    var nearLimitBudgets: [BudgetProgress] = []

    private let repo: any ITransactionRepository
    private let currencyService = CurrencyService()
    private var isLoaded = false
    private var categories: [CategorySnapshot] = []

    init(repo: any ITransactionRepository) {
        self.repo = repo
    }

    /// Handle to the in-flight fetch so tests (and callers) can await completion
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?

    /// Injectable so tests don't race on shared UserDefaults across parallel suites
    @ObservationIgnored var payCycleStartDay: () -> Int = { AppSettings.storedStartDay }

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
            transactions = try await txs
            categories = try await cats
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
        let (balance, income, expenses, recent) = await Task.detached(priority: .userInitiated) { [transactions, currencyService] in
            Self.computeMetrics(transactions, currencyService: currencyService, payCycleStartDay: payCycleStartDay)
        }.value

        totalBalance = balance
        monthlyIncome = income
        monthlyExpenses = expenses
        recentTransactions = recent
        anomalyCallout = Self.computeAnomalyCallout(
            transactions,
            payCycleStartDay: payCycleStartDay,
            dismissedKey: UserDefaults.standard.string(forKey: Self.dismissedAnomalyDefaultsKey)
        )
        nearLimitBudgets = Self.computeNearLimitBudgets(transactions, categories, payCycleStartDay: payCycleStartDay)
    }

    nonisolated private static func computeMetrics(
        _ transactions: [TransactionSnapshot],
        currencyService: CurrencyService,
        payCycleStartDay: Int
    ) -> (balance: Decimal, income: Decimal, expenses: Decimal, recent: [TransactionSnapshot]) {
        let (monthStart, monthEnd) = PayCycleService.currentFinancialMonth(startDay: payCycleStartDay)

        var balance = Decimal(0)
        var income = Decimal(0)
        var expenses = Decimal(0)
        var recent: [TransactionSnapshot] = []

        // ponytail: single pass — balance/metrics + O(n) top-5 (no full sort)
        for tx in transactions {
            let converted = currencyService.convertToBase(tx.amount, from: tx.currencyCode)
            balance += converted
            if tx.timestamp >= monthStart && tx.timestamp <= monthEnd {
                if tx.amount > 0 { income += converted }
                else if tx.amount < 0 { expenses += abs(converted) }
            }
            if recent.count < 5 || tx.timestamp > (recent.last?.timestamp ?? .distantPast) {
                recent.append(tx)
                recent.sort { $0.timestamp > $1.timestamp }
                if recent.count > 5 { recent.removeLast() }
            }
        }

        return (balance, income, expenses, recent)
    }

    private static let dismissedAnomalyDefaultsKey = "dismissedAnomalyCalloutKey"

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

    var financialMonthLabel: String {
        let startDay = AppSettings.storedStartDay
        guard startDay != 1 else { return String(localized: "This Month") }
        let (start, end) = PayCycleService.currentFinancialMonth(startDay: startDay)
        let startFormatted = start.formatted(.dateTime.month(.abbreviated).day())
        let endFormatted = end.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "This period · \(startFormatted) – \(endFormatted)")
    }

    var hasNoTransactions: Bool {
        transactions.isEmpty
    }

}
