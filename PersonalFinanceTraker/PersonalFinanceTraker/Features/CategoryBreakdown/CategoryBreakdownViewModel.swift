//
//  CategoryBreakdownViewModel.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/10/25.
//
import SwiftUI

@Observable @MainActor
final class CategoryBreakdownViewModel {
    var transactions: [TransactionModel] = []
    var selectedTimePeriod: TimePeriod = .month
    var selectedPieChartType: PieChartDataType = .expenses

    private let repo: ITransactionRepository
    private var dataService = PieChartDataService()
    
    init(repo: ITransactionRepository) {
        self.repo = repo
    }
    
    func load() {
        do {
            transactions = try repo.fetchAll()
        } catch { print(error) }
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
