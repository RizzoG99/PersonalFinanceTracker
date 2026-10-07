//
//  SafeToSpendSnapshotBuilder.swift
//  PersonalFinanceTraker
//

import Foundation

/// Safe to Spend until payday (#190). Every part is positive, in the base currency.
struct SafeToSpend: Equatable, Sendable {
    /// Recorded this cycle plus recurring income still due before payday.
    let income: Decimal
    let spent: Decimal
    /// Recurring expenses still due before payday, goal transfers excluded.
    let recurring: Decimal
    /// Recurring goal transfers (rules with a `goalId`) still due before payday.
    let goals: Decimal
    let buffer: Decimal
    let cycleStart: Date
    let payday: Date

    var amount: Decimal { income - spent - recurring - goals - buffer }
}

enum SafeToSpendSnapshotBuilder {
    static func compute(
        transactions: [TransactionSnapshot],
        activeRules: [RecurrenceRuleSnapshot],
        payCycleStartDay: Int,
        bufferPercent: Int,
        currencyService: CurrencyService,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SafeToSpend {
        let cycleStart = PayCycleService.financialMonthStart(for: now, startDay: payCycleStartDay, calendar: calendar)
        let payday = calendar.date(byAdding: .month, value: 1, to: cycleStart) ?? cycleStart
        let daysLeft = SafeToSpendSnapshot.daysLeft(from: now, until: payday, calendar: calendar)

        var income = Decimal.zero, spent = Decimal.zero, recurring = Decimal.zero, goals = Decimal.zero
        for tx in transactions where tx.timestamp >= cycleStart && tx.timestamp < payday {
            let amount = currencyService.convertToBase(tx.amount, from: tx.currencyCode)
            if amount > 0 { income += amount } else { spent -= amount }
        }
        // The timeline already skips what a rule's cursor marks as paid (forecast-only rules included).
        for charge in UpcomingCharge.timeline(rules: activeRules, now: now, days: daysLeft, calendar: calendar) {
            let amount = currencyService.convertToBase(charge.rule.amount, from: charge.rule.currencyCode)
            if amount > 0 { income += amount }
            else if charge.rule.goalId != nil { goals -= amount }
            else { recurring -= amount }
        }
        return SafeToSpend(
            income: income, spent: spent, recurring: recurring, goals: goals,
            buffer: income * Decimal(bufferPercent) / 100,
            cycleStart: cycleStart, payday: payday
        )
    }

    static func build(
        transactions: [TransactionSnapshot],
        activeRules: [RecurrenceRuleSnapshot],
        payCycleStartDay: Int,
        bufferPercent: Int,
        currencyService: CurrencyService,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SafeToSpendSnapshot {
        let safe = compute(
            transactions: transactions, activeRules: activeRules, payCycleStartDay: payCycleStartDay,
            bufferPercent: bufferPercent, currencyService: currencyService, now: now, calendar: calendar
        )
        return SafeToSpendSnapshot(generatedAt: now, currencyCode: currencyService.baseCurrency, amount: safe.amount, payday: safe.payday, hasIncome: safe.income > 0)
    }
}
