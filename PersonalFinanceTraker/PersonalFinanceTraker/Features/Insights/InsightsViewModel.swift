//
//  InsightsViewModel.swift
//  PersonalFinanceTraker
//

import Foundation
import Combine

final class InsightsViewModel: ObservableObject {
    @Published var transactions: [TransactionModel] = []
    @Published var chartData: [ChartDataPoint] = []
    @Published var topCategories: [PieChartDataPoint] = []
    @Published var trendData: [Double] = []
    @Published var averageIncome: Decimal = 0
    @Published var averageExpenses: Decimal = 0
    @Published var averageSavings: Decimal = 0

    let repo: ITransactionRepository
    private let chartDataService = ChartDataService()
    private let pieDataService = PieChartDataService()
    private let currencyService = CurrencyService()

    init(repo: ITransactionRepository) {
        self.repo = repo
    }

    func load() {
        do {
            transactions = try repo.fetchAll()
            loadChartData()
            loadTopCategories()
            loadTrendData()
            calculateAverages()
        } catch {
            print("InsightsViewModel load error: \(error)")
        }
    }

    private func loadChartData() {
        let all = chartDataService.generateChartData(from: transactions, for: .year)
        chartData = Array(all.suffix(6))
    }

    private func loadTopCategories() {
        let raw = pieDataService.generatePieChartData(
            from: transactions,
            for: .expenses,
            timePeriod: .year
        )
        topCategories = Array(raw.sorted { $0.amount > $1.amount }.prefix(5))
    }

    private func loadTrendData() {
        let calendar = Calendar.current
        trendData = (0..<6).reversed().map { offset in
            let start = calendar.date(byAdding: .month, value: -offset, to: Date())!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            let total = transactions
                .filter { $0.timestamp >= start && $0.timestamp < end && $0.amount < 0 }
                .reduce(Decimal(0)) { acc, tx in acc + currencyService.convertToBase(tx.amount, from: tx.currencyCode) }
            return Double(truncating: abs(total) as NSDecimalNumber)
        }
    }

    private func calculateAverages() {
        let calendar = Calendar.current
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        let recent = transactions.filter { $0.timestamp >= sixMonthsAgo }

        let totalIncome = recent.filter { $0.amount > 0 }.reduce(Decimal(0)) { acc, tx in
            acc + currencyService.convertToBase(tx.amount, from: tx.currencyCode)
        }
        let totalExpenses = abs(recent.filter { $0.amount < 0 }.reduce(Decimal(0)) { acc, tx in
            acc + currencyService.convertToBase(tx.amount, from: tx.currencyCode)
        })

        averageIncome = totalIncome / 6
        averageExpenses = totalExpenses / 6
        averageSavings = averageIncome - averageExpenses
    }
}
