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

    @Test func amountReturnsMatchingDayValue() {
        let today = day(0)
        let snapshot = SafeToSpendSnapshot(
            generatedAt: today,
            currencyCode: "EUR",
            payCycleEnd: today,
            days: [
                SafeToSpendDayValue(date: today, amount: 120),
                SafeToSpendDayValue(date: day(1), amount: 100)
            ]
        )
        #expect(SafeToSpendSnapshot.amount(for: day(1), from: snapshot) == 100)
    }

    @Test func amountReturnsNilWhenSnapshotIsMissing() {
        #expect(SafeToSpendSnapshot.amount(for: day(0), from: nil) == nil)
    }

    @Test func amountReturnsNilWhenDateIsPastLastCachedDay() {
        let today = day(0)
        let snapshot = SafeToSpendSnapshot(
            generatedAt: today,
            currencyCode: "EUR",
            payCycleEnd: today,
            days: [SafeToSpendDayValue(date: today, amount: 120)]
        )
        // Requesting day 6, but the snapshot only has day 0 cached — exhausted.
        #expect(SafeToSpendSnapshot.amount(for: day(6), from: snapshot) == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let today = day(0)
        let snapshot = SafeToSpendSnapshot(
            generatedAt: today,
            currencyCode: "EUR",
            payCycleEnd: today,
            days: (0..<7).map { SafeToSpendDayValue(date: day($0), amount: Decimal(100 - $0 * 5)) }
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SafeToSpendSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }
}
