//
//  SafeToSpendSnapshotTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

@Suite("SafeToSpendSnapshot")
struct SafeToSpendSnapshotTests {
    private func day(_ offset: Int, from base: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: base)!)
    }

    private func snapshot(amount: Decimal = 600, paydayIn days: Int = 20) -> SafeToSpendSnapshot {
        SafeToSpendSnapshot(generatedAt: day(0), currencyCode: "EUR", amount: amount, payday: day(days))
    }

    @Test func amountStaysValidUntilTheDayBeforePayday() {
        #expect(SafeToSpendSnapshot.projectedAmount(for: day(19), from: snapshot()) == 600)
    }

    @Test func amountExpiresOnPayday() {
        #expect(SafeToSpendSnapshot.projectedAmount(for: day(20), from: snapshot()) == nil)
    }

    @Test func perDaySpreadsOverTheDaysLeftIncludingToday() {
        let s = snapshot()
        #expect(SafeToSpendSnapshot.perDay(s.amount, from: day(0), until: s.payday) == 30)
        #expect(SafeToSpendSnapshot.perDay(s.amount, from: day(10), until: s.payday) == 60)
    }

    @Test func roundTripsThroughJSON() throws {
        let s = snapshot()
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(SafeToSpendSnapshot.self, from: data) == s)
    }
}
