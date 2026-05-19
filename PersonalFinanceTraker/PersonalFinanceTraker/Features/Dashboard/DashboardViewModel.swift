//
//  DashboardViewModel.swift
//  PersonalFinanceTraker
//

import Foundation
import Combine

final class DashboardViewModel: ObservableObject {
    @Published var transactions: [TransactionModel] = []
    @Published var totalBalance: Decimal = 0
    @Published var monthlyIncome: Decimal = 0
    @Published var monthlyExpenses: Decimal = 0
    @Published var recentTransactions: [TransactionModel] = []
    @Published var savingsGoal: Decimal = 5000
    @Published var currentSavings: Decimal = 0

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
            print("DashboardViewModel load error: \(error)")
        }
    }

    private func calculateMetrics() {
        totalBalance = transactions.reduce(Decimal(0)) { total, tx in
            total + currencyService.convertToBase(tx.amount, from: tx.currencyCode)
        }

        let now = Date()
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now

        let monthTx = transactions.filter { $0.timestamp >= monthStart && $0.timestamp < monthEnd }

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

    var savingsGoalProgress: Double {
        let denom = max(savingsGoal, currentSavings)
        guard denom > 0 else { return 0 }
        return Double(truncating: (currentSavings / denom) as NSDecimalNumber)
    }
}
