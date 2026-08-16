//
//  SafeToSpendSnapshotBuilder.swift
//  PersonalFinanceTraker
//

import Foundation

enum SafeToSpendSnapshotBuilder {
    /// Builds a seven-day cash-flow forecast. Day 0 is the current pay-cycle net;
    /// later days include future committed recurrence-rule occurrences.
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
            .reduce(Decimal.zero) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) }
        let today = calendar.startOfDay(for: now)

        let days: [SafeToSpendDayValue] = (0..<forwardDays).map { offset in
            let dayDate = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            guard offset > 0 else {
                return SafeToSpendDayValue(date: dayDate, amount: netSoFar)
            }
            let committed = activeRules.reduce(Decimal.zero) { total, rule in
                let occurrences = RecurrenceOccurrenceCalculator.occurrenceDates(
                    frequency: rule.frequency,
                    interval: rule.interval,
                    startDate: rule.startDate,
                    ruleEndDate: rule.endDate,
                    since: now,
                    through: dayDate,
                    calendar: calendar
                )
                return total + Decimal(occurrences.count) * currencyService.convertToBase(rule.amount, from: rule.currencyCode)
            }
            return SafeToSpendDayValue(date: dayDate, amount: netSoFar + committed)
        }

        return SafeToSpendSnapshot(
            generatedAt: now,
            currencyCode: currencyService.baseCurrency,
            forecastEnd: days.last?.date ?? today,
            days: days
        )
    }
}
