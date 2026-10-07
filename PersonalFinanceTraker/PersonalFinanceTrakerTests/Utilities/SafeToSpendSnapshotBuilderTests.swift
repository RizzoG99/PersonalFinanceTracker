//
//  SafeToSpendSnapshotBuilderTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

/// Pay cycle starts on the 27th; "today" is 7 Oct 2026, so the cycle is 27 Sep – 26 Oct.
@Suite("SafeToSpendSnapshotBuilder")
struct SafeToSpendSnapshotBuilderTests {
    private let calendar = Calendar.current
    private let currencyService = CurrencyService(defaults: UserDefaults(suiteName: "SafeToSpendSnapshotBuilderTests")!)

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func compute(
        _ transactions: [TransactionSnapshot] = [],
        rules: [RecurrenceRuleSnapshot] = [],
        buffer: Int = 5,
        now: Date? = nil
    ) -> SafeToSpend {
        SafeToSpendSnapshotBuilder.compute(
            transactions: transactions, activeRules: rules, payCycleStartDay: 27,
            bufferPercent: buffer, currencyService: currencyService, now: now ?? date(10, 7), calendar: calendar
        )
    }

    private var salary: TransactionSnapshot { .test(timestamp: date(9, 27), amount: 2_000, category: "Salary") }

    @Test func recordedIncomeMinusSpentMinusBuffer() {
        let safe = compute([salary, .test(timestamp: date(10, 1), amount: -600, category: "Food")])

        #expect(safe.income == 2_000)
        #expect(safe.spent == 600)
        #expect(safe.buffer == 100)
        #expect(safe.amount == 1_300)
        #expect(calendar.isDate(safe.payday, inSameDayAs: date(10, 27)))
    }

    @Test func zeroBufferReservesNothing() {
        #expect(compute([salary], buffer: 0).amount == 2_000)
    }

    @Test func salaryRuleStillDueThisCycleCountsAsIncome() {
        // New cycle started on the 27th, salary lands on the 28th.
        let rule = RecurrenceRuleSnapshot.test(startDate: date(9, 28), lastMaterializedDate: date(9, 28), amount: 2_000, category: "Salary")
        let safe = compute(rules: [rule], buffer: 0, now: date(10, 27, 9))

        #expect(safe.income == 2_000)
    }

    @Test func occurrenceOnOrAfterPaydayIsNotReserved() {
        let rule = RecurrenceRuleSnapshot.test(startDate: date(10, 27), amount: -400, category: "Rent")

        #expect(compute([salary], rules: [rule]).recurring == 0)
    }

    @Test func goalTransfersAreCountedOnceUnderGoals() {
        let goal = RecurrenceRuleSnapshot.test(startDate: date(10, 15), amount: -100, category: "→ Trip", goalId: UUID())
        let rent = RecurrenceRuleSnapshot.test(startDate: date(10, 20), amount: -400, category: "Rent")
        let safe = compute([salary], rules: [goal, rent])

        #expect(safe.goals == 100)
        #expect(safe.recurring == 400)
        // Decimal `==` reported a false mismatch here ("1400 == 1400" failed); compare the difference.
        #expect((safe.amount - (2_000 - 100 - 400 - 100)).isZero)
    }

    @Test func forecastOnlyRuleAlreadyMatchedIsNotReservedAgain() {
        // Paid early: the matched payment moved the cursor onto this cycle's occurrence.
        let paid = RecurrenceRuleSnapshot.test(startDate: date(10, 10), lastMaterializedDate: date(10, 10), autoRecord: false, amount: -240, category: "Loan")
        let unpaid = RecurrenceRuleSnapshot.test(startDate: date(10, 10), autoRecord: false, amount: -240, category: "Loan")

        #expect(compute([salary], rules: [paid]).recurring == 0)
        #expect(compute([salary], rules: [unpaid]).recurring == 240)
    }

    @Test func lastDayOfTheCycleIsInsideNextPaydayIsNot() {
        let lastDay = TransactionSnapshot.test(timestamp: date(10, 26, 23, 30), amount: -50, category: "Food")
        let payday = TransactionSnapshot.test(timestamp: date(10, 27, 0, 0), amount: -70, category: "Food")

        #expect(compute([salary, lastDay, payday], now: date(10, 26)).spent == 50)
    }

    @Test func overspendingGoesNegativeWithNoPerDayFigure() {
        let safe = compute([salary, .test(timestamp: date(10, 2), amount: -2_050, category: "Car")])

        #expect(safe.amount == -150)
        #expect(SafeToSpendSnapshot.perDay(safe.amount, from: date(10, 7), until: safe.payday) == nil)
    }

    @Test func snapshotCarriesTheSameAmountAsHome() {
        let snapshot = SafeToSpendSnapshotBuilder.build(
            transactions: [salary], activeRules: [], payCycleStartDay: 27, bufferPercent: 5,
            currencyService: currencyService, now: date(10, 7), calendar: calendar
        )

        #expect(snapshot.amount == compute([salary]).amount)
    }
}
