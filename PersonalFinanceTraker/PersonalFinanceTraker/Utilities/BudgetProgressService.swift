//  BudgetProgressService.swift
//  PersonalFinanceTraker

import Foundation
import SwiftData

struct BudgetProgress: Identifiable, Equatable, Sendable {
    let id: PersistentIdentifier
    let categoryName: String
    let systemImage: String
    let colorToken: String
    let budget: Decimal
    let spent: Decimal

    var percent: Double {
        guard budget > 0 else { return 0 }
        return Double(truncating: (spent / budget) as NSDecimalNumber)
    }

    var isOverBudget: Bool { spent > budget }
}

enum BudgetProgressService {
    static func computeProgress(
        categories: [CategorySnapshot],
        transactions: [TransactionSnapshot],
        payCycleStartDay: Int,
        calendar: Calendar = .current
    ) -> [BudgetProgress] {
        let budgeted = categories.filter {
            $0.transactionType == .expense && ($0.monthlyBudget ?? 0) > 0
        }
        guard !budgeted.isEmpty else { return [] }

        let (cycleStart, cycleEnd) = PayCycleService.currentFinancialMonth(
            startDay: payCycleStartDay, calendar: calendar
        )

        var spentByCategory: [String: Decimal] = [:]
        for tx in transactions where tx.amount < 0 {
            guard tx.timestamp >= cycleStart && tx.timestamp <= cycleEnd else { continue }
            spentByCategory[tx.category, default: 0] += abs(tx.amount)
        }

        return budgeted.map { category in
            BudgetProgress(
                id: category.persistentId,
                categoryName: category.name,
                systemImage: category.systemImage,
                colorToken: category.colorToken,
                budget: category.monthlyBudget ?? 0,
                spent: spentByCategory[category.name] ?? 0
            )
        }
    }

    static func nearLimit(_ progress: [BudgetProgress], threshold: Double = 0.8) -> [BudgetProgress] {
        progress.filter { $0.percent >= threshold }.sorted { $0.percent > $1.percent }
    }
}
