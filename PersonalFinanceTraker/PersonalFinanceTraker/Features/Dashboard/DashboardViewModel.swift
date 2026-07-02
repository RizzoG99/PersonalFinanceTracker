//
//  DashboardViewModel.swift
//  PersonalFinanceTraker
//

import Foundation

@Observable @MainActor
final class DashboardViewModel {
    var transactions: [TransactionModel] = []
    var totalBalance: Decimal = 0
    var monthlyIncome: Decimal = 0
    var monthlyExpenses: Decimal = 0
    var recentTransactions: [TransactionModel] = []
    var loadError: String? = nil

    private let repo: ITransactionRepository
    private let currencyService = CurrencyService()
    private var isLoaded = false

    init(repo: ITransactionRepository) {
        self.repo = repo
    }

    func load() {
        guard !isLoaded else { return }
        isLoaded = true  // ponytail: mark loaded before fetch; call reload() to retry after failure
        fetchAndCompute()
    }

    func reload() {
        isLoaded = false
        load()
    }

    private func fetchAndCompute() {
        do {
            transactions = try repo.fetchAll()
            calculateMetrics()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func optimisticRemove(_ items: [TransactionModel]) {
        let ids = Set(items.map(\.id))
        transactions.removeAll { ids.contains($0.id) }
        calculateMetrics()
    }

    private func calculateMetrics() {
        let payCycleStartDay = AppSettings.storedStartDay
        let (monthStart, monthEnd) = PayCycleService.currentFinancialMonth(startDay: payCycleStartDay)

        var balance = Decimal(0)
        var income = Decimal(0)
        var expenses = Decimal(0)
        var recent: [TransactionModel] = []

        // ponytail: single pass — balance/metrics + O(n) top-5 (no full sort)
        for tx in transactions {
            let converted = currencyService.convertToBase(tx.amount, from: tx.currencyCode)
            balance += converted
            if tx.timestamp >= monthStart && tx.timestamp <= monthEnd {
                if tx.amount > 0 { income += converted }
                else if tx.amount < 0 { expenses += abs(converted) }
            }
            if recent.count < 5 || tx.timestamp > recent.last!.timestamp {
                recent.append(tx)
                if recent.count > 5 { recent.removeLast() }
                recent.sort { $0.timestamp > $1.timestamp }
            }
        }

        totalBalance = balance
        monthlyIncome = income
        monthlyExpenses = expenses
        recentTransactions = recent
    }

    var financialMonthLabel: String {
        let startDay = AppSettings.storedStartDay
        guard startDay != 1 else { return "This Month" }
        let (start, _) = PayCycleService.currentFinancialMonth(startDay: startDay)
        return "Since \(start.formatted(.dateTime.month(.abbreviated).day()))"
    }

}
