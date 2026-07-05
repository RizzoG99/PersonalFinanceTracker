//
//  CategoryBreakdownViewModel.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/10/25.
//
import SwiftUI

@Observable @MainActor
final class CategoryBreakdownViewModel {
    var transactions: [TransactionSnapshot] = []
    var selectedTimePeriod: TimePeriod = .month
    var selectedPieChartType: PieChartDataType = .expenses
    var loadError: String? = nil

    private let repo: any ITransactionRepository
    private var dataService = PieChartDataService()

    init(repo: any ITransactionRepository) {
        self.repo = repo
    }

    func load() {
        Task {
            await fetchTransactions()
        }
    }

    private func fetchTransactions() async {
        do {
            transactions = try await repo.fetchAll()
        } catch { loadError = error.localizedDescription }
    }

    var summaryStats: (totalAmount: Decimal, categoryCount: Int) {
        dataService.getSummaryStats(
            from: transactions,
            for: selectedPieChartType,
            timePeriod: selectedTimePeriod,
            payCycleStartDay: AppSettings.storedStartDay
        )
    }

    var pieChartData: [PieChartDataPoint] {
        dataService.generatePieChartData(
            from: transactions,
            for: selectedPieChartType,
            timePeriod: selectedTimePeriod,
            payCycleStartDay: AppSettings.storedStartDay
        )
    }
}
