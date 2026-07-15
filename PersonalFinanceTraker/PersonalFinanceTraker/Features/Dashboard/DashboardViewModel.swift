//
//  DashboardViewModel.swift
//  PersonalFinanceTraker
//

import Foundation
import SwiftData

@Observable @MainActor
final class DashboardViewModel {
    var transactions: [TransactionSnapshot] = []
    var totalBalance: Decimal = 0
    var monthlyIncome: Decimal = 0
    var monthlyExpenses: Decimal = 0
    var recentTransactions: [TransactionSnapshot] = []
    var loadError: String? = nil

    private let repo: any ITransactionRepository
    private let currencyService = CurrencyService()
    private var isLoaded = false

    init(repo: any ITransactionRepository) {
        self.repo = repo
    }

    /// Handle to the in-flight fetch so tests (and callers) can await completion
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?

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
            transactions = try await repo.fetchAll()
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
        let payCycleStartDay = AppSettings.storedStartDay
        // ponytail: metrics computed off the MainActor from the already-fetched snapshots;
        // move aggregation into TransactionActor if the dataset ever makes the fetch itself the bottleneck
        let (balance, income, expenses, recent) = await Task.detached(priority: .userInitiated) { [transactions, currencyService] in
            Self.computeMetrics(transactions, currencyService: currencyService, payCycleStartDay: payCycleStartDay)
        }.value

        totalBalance = balance
        monthlyIncome = income
        monthlyExpenses = expenses
        recentTransactions = recent
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

    var financialMonthLabel: String {
        let startDay = AppSettings.storedStartDay
        guard startDay != 1 else { return "This Month" }
        let (start, end) = PayCycleService.currentFinancialMonth(startDay: startDay)
        let startFormatted = start.formatted(.dateTime.month(.abbreviated).day())
        let endFormatted = end.formatted(.dateTime.month(.abbreviated).day())
        return "This period · \(startFormatted) – \(endFormatted)"
    }

}
