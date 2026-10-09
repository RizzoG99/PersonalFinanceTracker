import Foundation

/// Materializes due `RecurrenceRule` occurrences into real `TransactionModel` rows, and moves
/// forecast-only rules' cursors past the occurrences a real payment has covered.
/// Launch/foreground-triggered only (see MainTabView) — no background execution,
/// matching how the daily log reminder already works.
actor RecurrenceMaterializationService {
    private var inFlight: Task<Void, Error>?

    /// Safe to call from multiple launch/foreground hooks in close succession: if a pass is
    /// already running, this call awaits it instead of starting a second *overlapping* pass
    /// that could read the same lastMaterializedDate cursor and double-insert. This guard is
    /// only about overlap — it does NOT collapse into a once-per-session no-op. Two calls that
    /// don't overlap (e.g. launch, then a foreground resume minutes later) each run a full,
    /// necessary pass so catch-up keeps working; don't "optimize" this into a run-once guard.
    func materialize(using repo: any ITransactionRepository, today: Date = .now, calendar: Calendar = .current) async throws {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task {
            try await Self.runMaterialization(using: repo, today: today, calendar: calendar)
        }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }

    private static func runMaterialization(using repo: any ITransactionRepository, today: Date, calendar: Calendar) async throws {
        let rules = try await repo.fetchActiveRecurrenceRules()
        // Forecast-only fixed expenses (#188) never insert: their cursor follows real payments.
        let forecastOnly = rules.filter { !$0.autoRecord }
        if !forecastOnly.isEmpty {
            let transactions = try await repo.fetchAll()
            for rule in forecastOnly {
                guard let paid = RecurrenceDetector.paidThrough(rule: rule, transactions: transactions, today: today, calendar: calendar) else { continue }
                try await repo.advanceRecurrenceRule(id: rule.id, cursor: paid.cursor, amount: paid.amount)
            }
        }
        for rule in rules where rule.autoRecord {
            let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
                frequency: rule.frequency,
                interval: rule.interval,
                startDate: rule.startDate,
                ruleEndDate: rule.endDate,
                since: rule.lastMaterializedDate,
                through: today,
                calendar: calendar
            )
            guard let newCursor = dates.last else { continue }
            let inputs = dates.map { occurrenceDate in
                TransactionInput(
                    timestamp: occurrenceDate,
                    amount: rule.amount,
                    note: rule.note,
                    category: rule.category,
                    currencyCode: rule.currencyCode,
                    goalId: rule.goalId,
                    categoryPersistentId: rule.categoryId,
                    recurrenceRuleId: rule.id
                )
            }
            try await repo.materializeOccurrences(ruleId: rule.id, inputs: inputs, newCursor: newCursor)
        }
    }
}
