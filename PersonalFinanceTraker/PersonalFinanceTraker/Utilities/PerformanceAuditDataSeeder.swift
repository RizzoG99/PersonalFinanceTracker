//
//  PerformanceAuditDataSeeder.swift
//  PersonalFinanceTraker
//

import Foundation
import SwiftData

/// Creates a repeatable ledger in a Debug simulator or the isolated TEST app.
/// Physical-device/optimized seeding is available only in PFT_TEST_BUILD configurations.
/// Requires an explicit `-seedPerformanceAuditData <count>` launch argument.
enum PerformanceAuditDataSeeder {
    @MainActor
    static func seedIfRequested(in container: ModelContainer) {
        #if PFT_TEST_BUILD || (DEBUG && targetEnvironment(simulator))
        let arguments = ProcessInfo.processInfo.arguments
        guard let countIndex = arguments.firstIndex(of: "-seedPerformanceAuditData"),
              arguments.indices.contains(countIndex + 1),
              let count = Int(arguments[countIndex + 1]),
              [1_000, 5_000, 20_000].contains(count)
        else { return }

        let anchor = anchorDate(arguments: arguments)
        let context = container.mainContext

        do {
            try context.delete(model: TransactionModel.self)
            try context.delete(model: CategoryModel.self)
            try context.delete(model: GoalModel.self)
            try context.delete(model: TravelModel.self)
            try context.delete(model: HealthScoreSnapshot.self)
            try context.delete(model: RecurrenceRule.self)
            try context.delete(model: MerchantCategoryMapping.self)
            try context.save()

            let categories = SampleData.createSampleCategories()
            for category in categories {
                if ["Groceries", "Restaurants", "Gas", "Streaming Services"].contains(category.name) {
                    category.monthlyBudget = 400
                }
                context.insert(category)
            }

            let incomeCategories = categories
                .filter { $0.transactionType == .income }
                .sorted { $0.name < $1.name }
            let expenseCategories = categories
                .filter { $0.transactionType == .expense }
                .sorted { $0.name < $1.name }

            for index in 0..<count {
                let isIncome = index.isMultiple(of: 20)
                let pool = isIncome ? incomeCategories : expenseCategories
                let category = pool[index % pool.count]
                let cents = isIncome
                    ? 180_000 + ((index * 7_919) % 220_000)
                    : 250 + ((index * 7_919) % 24_750)
                let amount = Decimal(isIncome ? cents : -cents) / 100
                let timestamp = transactionDate(index: index, anchor: anchor)
                context.insert(TransactionModel(
                    timestamp: timestamp,
                    amount: amount,
                    note: "Performance fixture \(index)",
                    category: category.name,
                    categoryModel: category,
                    currencyCode: "EUR"
                ))
            }

            try context.save()
            do {
                try PINService().setPIN("1234")
                UserDefaults.standard.set(true, forKey: "pin_setup_complete")
                UserDefaults.standard.set(false, forKey: "biometric_lock_enabled")
            } catch {
                PerformanceAuditRecorder.event(
                    "Dataset.pin.failed",
                    metadata: "error=\(error.localizedDescription)"
                )
            }
            PerformanceAuditRecorder.event(
                "Dataset.seed.completed",
                metadata: "transactions=\(count) anchor_epoch=\(Int(anchor.timeIntervalSince1970))"
            )
        } catch {
            PerformanceAuditRecorder.event(
                "Dataset.seed.failed",
                metadata: "error=\(error.localizedDescription)"
            )
        }
        #endif
    }

    #if PFT_TEST_BUILD || (DEBUG && targetEnvironment(simulator))
    private static func anchorDate(arguments: [String]) -> Date {
        guard let index = arguments.firstIndex(of: "-performanceAuditAnchorEpoch"),
              arguments.indices.contains(index + 1),
              let interval = TimeInterval(arguments[index + 1])
        else { return .now }
        return Date(timeIntervalSince1970: interval)
    }

    private static func transactionDate(index: Int, anchor: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayOffset = index % (365 * 5)
        let secondOffset = (index * 7_919) % (24 * 60 * 60)
        let day = calendar.date(byAdding: .day, value: -dayOffset, to: anchor) ?? anchor
        return calendar.date(byAdding: .second, value: secondOffset, to: day) ?? day
    }
    #endif
}
