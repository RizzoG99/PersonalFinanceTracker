//
//  CategoryBreakdownViewModel.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/10/25.
//
import Combine
import SwiftUI

final class CategoryBreakdownViewModel: ObservableObject {
    
    @Published var transactions: [TransactionModel] = []
    @Published var selectedTimePeriod: TimePeriod = .month
    @Published var selectedPieChartType: PieChartDataType = .expenses
    
    private let repo: ITransactionRepository
    private var cancellables = Set<AnyCancellable>()
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
            timePeriod: selectedTimePeriod
        )
    }
    
    var pieChartData: [PieChartDataPoint] {
        dataService.generatePieChartData(
            from: transactions,
            for: selectedPieChartType,
            timePeriod: selectedTimePeriod
        )
    }
}
