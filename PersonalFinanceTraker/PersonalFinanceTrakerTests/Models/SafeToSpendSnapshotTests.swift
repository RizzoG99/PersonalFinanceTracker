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
            forecastEnd: day(1),
            days: [
                SafeToSpendDayValue(date: today, amount: 120),
                SafeToSpendDayValue(date: day(1), amount: 100)
            ]
        )
        #expect(SafeToSpendSnapshot.amount(for: day(1), from: snapshot) == 100)
    }

    @Test func projectedAmountUsesTheForecastEndValue() {
        let today = day(0)
        let forecastEnd = day(6)
        let snapshot = SafeToSpendSnapshot(
            generatedAt: today,
            currencyCode: "EUR",
            forecastEnd: forecastEnd,
            days: [
                SafeToSpendDayValue(date: today, amount: 120),
                SafeToSpendDayValue(date: forecastEnd, amount: 75)
            ]
        )

        #expect(SafeToSpendSnapshot.projectedAmount(for: today, from: snapshot) == 75)
    }

    @Test func projectedAmountExpiresAfterTheForecastHorizon() {
        let today = day(0)
        let snapshot = SafeToSpendSnapshot(
            generatedAt: today,
            currencyCode: "EUR",
            forecastEnd: today,
            days: [SafeToSpendDayValue(date: today, amount: 120)]
        )

        #expect(SafeToSpendSnapshot.projectedAmount(for: day(1), from: snapshot) == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let today = day(0)
        let snapshot = SafeToSpendSnapshot(
            generatedAt: today,
            currencyCode: "EUR",
            forecastEnd: day(6),
            days: (0..<7).map { SafeToSpendDayValue(date: day($0), amount: Decimal(100 - $0 * 5)) }
        )
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(SafeToSpendSnapshot.self, from: data) == snapshot)
    }
}
