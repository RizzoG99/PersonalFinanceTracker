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
    var savingsGoal: Decimal = 5000
    var currentSavings: Decimal = 0
    var loadError: String? = nil

    let repo: ITransactionRepository
    private let currencyService = CurrencyService()

    init(repo: ITransactionRepository) {
        self.repo = repo
    }

    func load() {
        do {
            transactions = try repo.fetchAll()
            calculateMetrics()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func calculateMetrics() {
        totalBalance = transactions.reduce(Decimal(0)) { total, tx in
            total + currencyService.convertToBase(tx.amount, from: tx.currencyCode)
        }

        let payCycleStartDay = AppSettings.storedStartDay
        let (monthStart, monthEnd) = PayCycleService.currentFinancialMonth(startDay: payCycleStartDay)
        let monthTx = transactions.filter { $0.timestamp >= monthStart && $0.timestamp <= monthEnd }

        monthlyIncome = monthTx.filter { $0.amount > 0 }.reduce(Decimal(0)) { total, tx in
            total + currencyService.convertToBase(tx.amount, from: tx.currencyCode)
        }

        monthlyExpenses = abs(monthTx.filter { $0.amount < 0 }.reduce(Decimal(0)) { total, tx in
            total + currencyService.convertToBase(tx.amount, from: tx.currencyCode)
        })

        let allIncome = transactions.filter { $0.amount > 0 }.reduce(Decimal(0)) { total, tx in
            total + currencyService.convertToBase(tx.amount, from: tx.currencyCode)
        }
        let allExpenses = abs(transactions.filter { $0.amount < 0 }.reduce(Decimal(0)) { total, tx in
            total + currencyService.convertToBase(tx.amount, from: tx.currencyCode)
        })
        currentSavings = allIncome - allExpenses

        recentTransactions = Array(transactions.sorted { $0.timestamp > $1.timestamp }.prefix(5))
    }

    var financialMonthLabel: String {
        let startDay = AppSettings.storedStartDay
        guard startDay != 1 else { return "This Month" }
        let (start, _) = PayCycleService.currentFinancialMonth(startDay: startDay)
        return "Since \(start.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var savingsGoalProgress: Double {
        let denom = max(savingsGoal, currentSavings)
        guard denom > 0 else { return 0 }
        return Double(truncating: (currentSavings / denom) as NSDecimalNumber)
    }
}
