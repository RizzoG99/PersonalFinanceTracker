//
//  SafeToSpendSnapshotBuilder.swift
//  PersonalFinanceTraker
//

import Foundation

enum SafeToSpendSnapshotBuilder {
    /// Builds a 7-day-forward safe-to-spend projection. Day 0 (today) is the current
    /// pay-cycle net (income - expenses so far this cycle, via `TransactionSnapshot`s that
    /// already include anything materialized). Days 1-6 subtract/add committed amounts from
    /// active `RecurrenceRule`s whose occurrence date falls in that window — those haven't
    /// been materialized into real transactions yet (materialization only runs through
    /// "today"), so counting them here without double-counting is safe.
    static func build(
        transactions: [TransactionSnapshot],
        activeRules: [RecurrenceRuleSnapshot],
        payCycleStartDay: Int,
        currencyService: CurrencyService,
        now: Date = .now,
        calendar: Calendar = .current,
        forwardDays: Int = 7
    ) -> SafeToSpendSnapshot {
        let (cycleStart, cycleEnd) = PayCycleService.currentFinancialMonth(startDay: payCycleStartDay, calendar: calendar)

        let netSoFar = transactions
            .filter { $0.timestamp >= cycleStart && $0.timestamp <= cycleEnd }
            .reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) }

        let today = calendar.startOfDay(for: now)

        let days: [SafeToSpendDayValue] = (0..<forwardDays).map { offset in
            let dayDate = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            guard offset > 0 else {
                return SafeToSpendDayValue(date: dayDate, amount: netSoFar)
            }
            let committed = activeRules.reduce(Decimal(0)) { total, rule in
                let occurrences = RecurrenceOccurrenceCalculator.occurrenceDates(
                    frequency: rule.frequency,
                    interval: rule.interval,
                    startDate: rule.startDate,
                    ruleEndDate: rule.endDate,
                    since: now,
                    through: dayDate,
                    calendar: calendar
                )
                guard !occurrences.isEmpty else { return total }
                return total + Decimal(occurrences.count) * currencyService.convertToBase(rule.amount, from: rule.currencyCode)
            }
            return SafeToSpendDayValue(date: dayDate, amount: netSoFar + committed)
        }

        return SafeToSpendSnapshot(generatedAt: now, currencyCode: currencyService.baseCurrency, payCycleEnd: cycleEnd, days: days)
    }
}
