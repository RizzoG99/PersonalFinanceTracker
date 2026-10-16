//
//  CycleSummaryServiceTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

@MainActor
struct CycleSummaryServiceTests {
    @Test("only the current and three comparison cycles need currency conversion")
    func conversionWorkIsBoundedToRelevantCycles() throws {
        let old = Calendar.current.date(from: DateComponents(year: 2020, month: 1, day: 1))!
        let currency = CycleSummaryCountingCurrencyService()
        currency.baseCurrency = "EUR"
        let transactions: [TransactionSnapshot] = [
            .test(timestamp: old, amount: 1, category: "Salary"),
            .test(timestamp: old.addingTimeInterval(86_400), amount: -999, category: "Old"),
            tx(-10, 1, 1), tx(-20, 1, 2), tx(-30, 1, 3),
            tx(2000, 1, category: "Salary"), tx(-40, 10), tx(-50, 25),
            tx(-999, 1, 5),
        ]
        let result = try #require(CycleSummaryService.compute(
            transactions: transactions, payCycleStartDay: 1, currencyService: currency, now: date(20)
        ))
        #expect(currency.conversionCount == 6)
        #expect(result == CycleSummary(
            income: 2000, out: 90, spentSoFar: 40, pace: .faster,
            usualSoFar: 20, usualFullCycle: 20,
            categories: [.init(category: "🛒 Groceries", spent: 40, delta: 20)],
            dailyCumulative: Array(repeating: 0, count: 9) + Array(repeating: 40, count: 11),
            cycleStart: date(1), payday: date(1, 5)
        ))
    }

    @Test("windowing preserves pay-cycle edges, DST, currency conversion and future spending")
    func boundedWindowPreservesCalendarAndDecimalResults() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        func fixedDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
        func entry(_ amount: Decimal, _ year: Int, _ month: Int, _ day: Int,
                   currency: String = "EUR") -> TransactionSnapshot {
            .test(timestamp: fixedDate(year, month, day), amount: amount,
                  category: "Groceries", currencyCode: currency)
        }
        let old = fixedDate(2020, 1, 1)
        let currentStart = calendar.startOfDay(for: fixedDate(2024, 3, 27))
        let payday = calendar.startOfDay(for: fixedDate(2024, 4, 27))
        let fullHistory: [TransactionSnapshot] = [
            .test(timestamp: old, amount: 1, category: "Salary"),
            entry(-999, 2023, 12, 26), // before the three comparison cycles
            entry(Decimal(string: "-10.80")!, 2023, 12, 27, currency: "USD"),
            entry(-20, 2024, 1, 27), entry(-30, 2024, 2, 27),
            .test(timestamp: currentStart, amount: 2000, category: "Salary"),
            entry(-40, 2024, 3, 31), // DST switch inside the current cycle
            entry(-50, 2024, 4, 25), // future, still included in out
            .test(timestamp: payday, amount: -999, category: "Next cycle"),
        ]
        let currency = CycleSummaryCountingCurrencyService()
        currency.baseCurrency = "EUR"
        let result = try #require(CycleSummaryService.compute(
            transactions: fullHistory, payCycleStartDay: 27, currencyService: currency,
            now: fixedDate(2024, 4, 20), calendar: calendar
        ))
        #expect(currency.conversionCount == 6)
        #expect(result.income == 2000)
        #expect(result.out == 90)
        #expect(result.spentSoFar == 40)
        #expect(result.usualSoFar == 20)
        #expect(result.usualFullCycle == 20)
        #expect(result.projected == 40)
        #expect(result.pace == .faster)
        #expect(result.cycleStart == currentStart)
        #expect(result.payday == payday)
        #expect(result.dailyCumulative == Array(repeating: 0, count: 4) + Array(repeating: 40, count: 21))
    }

    // Fixed 2024 dates: March/April avoid the EU DST switch, and the US one (Mar 10) only shifts
    // a same-point cutoff by an hour — none of the fixtures sit that close to a cutoff.
    private func date(_ day: Int, _ month: Int = 4, hour: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2024, month: month, day: day, hour: hour))!
    }

    private func tx(_ amount: Decimal, _ day: Int, _ month: Int = 4, hour: Int = 0,
                    category: String = "🛒 Groceries", goalId: UUID? = nil) -> TransactionSnapshot {
        .test(timestamp: date(day, month, hour: hour), amount: amount, category: category, goalId: goalId)
    }

    private func summary(_ transactions: [TransactionSnapshot], now: Date, startDay: Int = 1) -> CycleSummary? {
        CycleSummaryService.compute(
            transactions: transactions, payCycleStartDay: startDay,
            currencyService: CurrencyService(), now: now
        )
    }

    @Test("goal transfers count as saved, not out")
    func goalTransferIsSaved() throws {
        let s = try #require(summary([
            tx(2000, 1, category: "💼 Salary"), tx(-300, 5), tx(-200, 6, category: "→ Holiday", goalId: UUID()),
        ], now: date(20)))
        #expect(s.income == 2000)
        #expect(s.out == 300)
        #expect(s.saved == 1700)
    }

    @Test("nothing recorded this cycle hides the card")
    func emptyCycleIsNil() {
        #expect(summary([tx(-50, 5, 2)], now: date(20)) == nil)
    }

    @Test("a transaction on the cycle's last day is included")
    func lastDayIncluded() throws {
        let s = try #require(summary([tx(-40, 30, hour: 10)], now: date(30, hour: 12)))
        #expect(s.out == 40)
    }

    @Test("uses the pay cycle, not the calendar month")
    func respectsPayCycleStartDay() throws {
        let s = try #require(summary([tx(-40, 12), tx(-999, 5)], now: date(20), startDay: 10))
        #expect(s.cycleStart == date(10))
        #expect(s.out == 40)
    }

    /// #154: comparing so-far against a *complete* earlier cycle read identical pace as a drop.
    /// The cycles before recording started (Jan, Feb) must not count either.
    @Test("identical pace against a partial earlier cycle reads on track")
    func samePointComparison() throws {
        let april = [1, 6, 11, 16].map { tx(-50, $0) }
        let march = [1, 6, 11, 16, 21, 26].map { tx(-50, $0, 3) }
        let s = try #require(summary(april + march, now: date(20)))
        #expect(s.usualSoFar == 200)
        #expect(s.usualFullCycle == 300)
        #expect(s.pace == .onTrack)
    }

    /// #154: a future-dated (materialized recurring) expense hasn't happened yet.
    @Test("future-dated spending counts as out but not towards pace")
    func futureDatedExcludedFromPace() throws {
        let s = try #require(summary([tx(-50, 10), tx(-5000, 25), tx(-50, 10, 3), tx(1, 1, 3)], now: date(20)))
        #expect(s.out == 5050)
        #expect(s.spentSoFar == 50)
        #expect(s.pace == .onTrack)
    }

    @Test("no verdict in the first week")
    func buildingEarly() throws {
        let s = try #require(summary([tx(-500, 1), tx(-5, 1, 3)], now: date(2)))
        #expect(s.pace == .building)
    }

    @Test("an earlier cycle with no spending so far gives no verdict")
    func buildingWithoutUsual() throws {
        let s = try #require(summary([tx(-100, 5), tx(1000, 1, 3)], now: date(20)))
        #expect(s.pace == .building)
    }

    /// Jan 100, Feb 100, Mar 160 → usual 120; 140 is > +10%. Against March alone it wouldn't be.
    @Test("usual is the average of up to three earlier cycles")
    func averagesThreeCycles() throws {
        let s = try #require(summary([
            tx(1, 1, 1), tx(-100, 5, 1), tx(-100, 5, 2), tx(-160, 5, 3), tx(-140, 5),
        ], now: date(20)))
        #expect(s.usualSoFar == 120)
        #expect(s.pace == .faster)
    }

    @Test("faster names the top two categories driving it, and projects from the usual")
    func fasterWithDrivers() throws {
        let s = try #require(summary([
            tx(-100, 5, category: "🍽️ Restaurants"), tx(-60, 6, category: "🚗 Transport"), tx(-50, 7),
            tx(-20, 1, 3, category: "🍽️ Restaurants"), tx(-20, 6, 3, category: "🚗 Transport"), tx(-50, 7, 3),
        ], now: date(20)))
        #expect(s.pace == .faster)
        #expect(s.drivers.map(\.category) == ["🍽️ Restaurants", "🚗 Transport"])
        #expect(s.drivers.map(\.delta) == [80, 40])
        #expect(s.projected == 210)
        // The detail's full list: every category, biggest spend first, flat ones included.
        #expect(s.categories.map(\.category) == ["🍽️ Restaurants", "🚗 Transport", "🛒 Groceries"])
        #expect(s.categories.last?.delta == 0)
    }

    @Test("on track names no drivers")
    func onTrackHasNoDrivers() throws {
        let s = try #require(summary([tx(-100, 5), tx(-100, 1, 3)], now: date(20)))
        #expect(s.pace == .onTrack)
        #expect(s.drivers.isEmpty)
    }
}

private final class CycleSummaryCountingCurrencyService: CurrencyService {
    private(set) var conversionCount = 0

    override func convertToBase(_ amount: Decimal, from source: String) -> Decimal {
        conversionCount += 1
        return super.convertToBase(amount, from: source)
    }
}
