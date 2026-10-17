import Foundation
import SwiftData
import Testing
@testable import PersonalFinanceTraker

extension PerformanceRecorderSerialTests {
/// Run alone: the recorder and app settings are process-wide. This isolates actual
/// ViewModel analytics from SwiftData I/O and SwiftUI layout; it is not tap-to-frame latency.
@Suite(.serialized)
struct AnalyticsBaselineTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PFT_ANALYTICS_BASELINE"] == "1"
                   && Bundle.main.bundleIdentifier == "rizzoG99.PersonalFinanceTraker.test"))
    @MainActor func fiveThousandTransactions() async throws {
        let defaults = UserDefaults.standard
        let settingKeys = ["payCycleStartDay", "healthScore.ignoreSubscriptions", "reminderEnabled", "app_base_currency",
                           "dismissedAnomalyCalloutKey", "dismissedDailyLoggingReminderPrompt", "financialPulseNoSpendDateKeys"]
        let saved = settingKeys.map { ($0, defaults.object(forKey: $0)) }
        let widgetDefaults = try #require(UserDefaults(suiteName: AppGroup.identifier))
        let priorWidget = widgetDefaults.object(forKey: "dailyLoggingHabitSnapshot")
        let wasEnabled = PerformanceAuditRecorder.isEnabled
        defer {
            for (key, value) in saved { defaults.set(value, forKey: key) }
            widgetDefaults.set(priorWidget, forKey: "dailyLoggingHabitSnapshot")
            PerformanceAuditRecorder.resetForTesting(isEnabled: wasEnabled)
        }
        defaults.set(false, forKey: "healthScore.ignoreSubscriptions")
        defaults.set("EUR", forKey: "app_base_currency")
        defaults.set(false, forKey: "reminderEnabled")
        defaults.removeObject(forKey: "dismissedAnomalyCalloutKey")
        defaults.removeObject(forKey: "dismissedDailyLoggingReminderPrompt")

        let schema = Schema([TransactionModel.self, CategoryModel.self, CreditCardModel.self,
                             GoalModel.self, TravelModel.self, HealthScoreSnapshot.self,
                             RecurrenceRule.self, MerchantCategoryMapping.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let context = container.mainContext
        context.autosaveEnabled = false
        SampleData.populateModelContext(context)
        try context.delete(model: TransactionModel.self)
        let categories = try context.fetch(FetchDescriptor<CategoryModel>(sortBy: [SortDescriptor(\.name)]))
        for category in categories where ["Groceries", "Restaurants", "Gas", "Streaming Services"].contains(category.name) {
            category.monthlyBudget = 400
        }
        let expenses = categories.filter { $0.transactionType == .expense }
        let income = categories.filter { $0.transactionType == .income }
        let anchor = Date(timeIntervalSince1970: 1_791_547_200)
        var models: [TransactionModel] = []
        for index in 0..<5_000 {
            let isIncome = index.isMultiple(of: 20)
            let pool = isIncome ? income : expenses
            let category = pool[index % pool.count]
            let cents = isIncome ? 180_000 + ((index * 7_919) % 220_000) : 250 + ((index * 7_919) % 24_750)
            let model = TransactionModel(
                timestamp: anchor.addingTimeInterval(-Double(index % 1_825) * 86_400 + Double((index * 7_919) % 86_400)),
                amount: Decimal(isIncome ? cents : -cents) / 100,
                note: "Performance fixture \(index)", category: category.name, categoryModel: category, currencyCode: "EUR"
            )
            context.insert(model)
            models.append(model)
        }
        try context.save()
        let original = models.map(TransactionSnapshot.init)
        models[1].amount -= Decimal(string: "123.45")!
        let mutated = models.map(TransactionSnapshot.init)
        let today = Calendar.current.startOfDay(for: .now)
        var reference: [String: String] = [:]

        // Round -1 verifies disabled instrumentation result parity. Round 0 is first
        // instrumented use; 1...5 are warm repeats. Inputs/settings are reset each round.
        for round in -1...5 {
            defaults.set(1, forKey: "payCycleStartDay")
            PerformanceAuditRecorder.resetForTesting(isEnabled: round >= 0)
            let repo = MockTransactionRepository()
            repo.stubbedTransactions = original
            repo.stubbedCategories = categories.map(CategorySnapshot.init)
            let home = DashboardViewModel(repo: repo)
            home.currentDate = { anchor }
            home.noSpendDateKeys = { [] }
            home.bufferPercent = { 10 }
            let insights = CompassViewModel(repo: repo)

            func capture(_ action: String, _ operation: () async -> Void) async throws {
                let before = PerformanceAuditRecorder.testingSnapshot()
                let fetches = repo.fetchAllCallCount
                let start = ContinuousClock.now
                await operation()
                let duration = start.duration(to: .now)
                let after = PerformanceAuditRecorder.testingSnapshot()
                let result = try signature(home: home, insights: insights)
                if round == -1 { reference[action] = result }
                else { #expect(result == reference[action], "Result parity for \(action), round \(round)") }
                #expect(Calendar.current.startOfDay(for: .now) == today, "Reject a run crossing midnight")
                let samples = Array(after.synchronousSamples.dropFirst(before.synchronousSamples.count))
                #expect(samples.filter { $0.name != "Dashboard.recent" }.allSatisfy { $0.isMainThread })
                let isPeriodChange = ["Insights.previousMonth", "Insights.year", "Insights.week"].contains(action)
                let isReturn = action == "Home.return"
                #expect(repo.fetchAllCallCount - fetches == (isReturn || isPeriodChange ? 0 : 1))
                #expect(samples.count == (round < 0 || isReturn ? 0 : isPeriodChange ? 1 : action.hasPrefix("Home.") ? 11 : 6))
                #expect(after.activeIntervals.values.allSatisfy { $0 == 0 })
                let sampleData = try JSONEncoder().encode(samples)
                let record: [String: Any] = [
                    "round": round, "action": action, "input_count": repo.stubbedTransactions.count,
                    "wall_ms": Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15,
                    "fetch_count": repo.fetchAllCallCount - fetches,
                    "samples": try JSONSerialization.jsonObject(with: sampleData),
                    "result": try JSONSerialization.jsonObject(with: Data(result.utf8)),
                    "observed_epoch": Date.now.timeIntervalSince1970,
                    "timezone": TimeZone.current.identifier, "locale": Locale.current.identifier
                ]
                print("PFT_ANALYTICS_BASELINE \(String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self))")
            }

            try await capture("Home.initial") { home.load(); await home.loadTask?.value }
            try await capture("Home.return") { home.load(); await home.loadTask?.value }
            try await capture("Insights.navigation") { await insights.reloadData() }
            try await capture("Insights.previousMonth") { insights.explorerPeriod = insights.explorerPeriod.previous() }
            try await capture("Insights.year") { insights.explorerPeriod = .current(.year, now: anchor) }
            try await capture("Insights.week") { insights.explorerPeriod = .current(.week, now: anchor) }
            try await capture("Home.payCycle") {
                defaults.set(27, forKey: "payCycleStartDay")
                home.reload(); await home.loadTask?.value
            }
            try await capture("Insights.payCycle") { await insights.reloadData() }
            let selectedPeriod = insights.explorerPeriod
            let previousSpent = try #require(home.safeToSpend?.spent)
            repo.stubbedTransactions = mutated
            try await capture("Home.mutation") { home.reload(); await home.loadTask?.value }
            try await capture("Insights.mutation") { await insights.reloadData() }
            #expect(home.safeToSpend?.spent == previousSpent + Decimal(string: "123.45")!)
            #expect(insights.explorerPeriod == selectedPeriod)
            #expect(home.transactions.first(where: { $0.id == mutated[1].id })?.amount == mutated[1].amount)
            #expect(insights.transactions.first(where: { $0.id == mutated[1].id })?.amount == mutated[1].amount)
            let explorerItems = mutated.filter {
                $0.timestamp >= insights.explorerPeriod.interval.start && $0.timestamp < insights.explorerPeriod.interval.end && $0.amount < 0 && $0.goalId == nil
            }
            #expect(insights.explorer.total == explorerItems.reduce(Decimal.zero) { $0 - $1.amount })
            #expect(insights.explorer.bars.reduce(Decimal.zero) { $0 + $1.amount } == insights.explorer.total)
        }
    }

    @MainActor private func signature(home: DashboardViewModel, insights: CompassViewModel) throws -> String {
        let result: [String: Any] = [
            "home_income": home.safeToSpend?.income.description ?? "nil",
            "home_spent": home.safeToSpend?.spent.description ?? "nil",
            "cycle_income": home.cycleSummary?.income.description ?? "nil",
            "cycle_out": home.cycleSummary?.out.description ?? "nil",
            "check_in": String(describing: home.dailyCheckInStatus),
            "score": insights.healthScore?.score ?? -1,
            "components": insights.healthScore?.components.map(\.score) ?? [],
            "average_income": insights.averageIncome.description,
            "average_expenses": insights.averageExpenses.description,
            "average_savings": insights.averageSavings.description,
            "recap_spent": insights.monthlyRecap?.spent.description ?? "nil",
            "recap_income": insights.monthlyRecap?.income.description ?? "nil",
            "explorer_total": insights.explorer.total.description,
            "bars": insights.explorer.bars.map { ["date": String($0.date.timeIntervalSince1970), "amount": $0.amount.description] },
            "categories": insights.explorer.trends.map { ["category": $0.category.category, "amount": $0.category.amount.description] }.sorted { $0["category"]! < $1["category"]! }
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self)
    }
}
}
