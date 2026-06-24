import Testing
import Foundation
@testable import PersonalFinanceTraker

struct SpendingForecastServiceTests {
    private let service = SpendingForecastService(currencyService: CurrencyService())
    private let cal = Calendar.current

    private func date(year: Int, month: Int, day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func tx(on date: Date, amount: Double) -> TransactionModel {
        TransactionModel(
            timestamp: date, amount: Decimal(amount),
            note: "", category: "Food", currencyCode: "EUR", goalId: nil
        )
    }

    @Test("nil cache computes all elapsed days")
    func nilCacheFullRecompute() {
        let now = date(year: 2026, month: 6, day: 15)
        let transactions = [
            tx(on: date(year: 2026, month: 6, day: 1), amount: -50),
            tx(on: date(year: 2026, month: 6, day: 10), amount: -30),
        ]

        let (forecast, cache) = service.compute(expenseTransactions: transactions, cache: nil, now: now)

        #expect(cache.monthKey == "2026-06")
        #expect(cache.computedUpToDay == 15)
        #expect(cache.days.count == 15)
        #expect(cache.amounts[0] == 50.0)   // day 1: 50
        #expect(cache.amounts[9] == 80.0)   // day 10: 50 + 30
        #expect(cache.amounts[14] == 80.0)  // day 15: no new spend
        #expect(forecast.dailyActuals.count == 15)
    }

    @Test("cache hit appends only days after computedUpToDay")
    func cacheHitAppendsNewDaysOnly() {
        let now = date(year: 2026, month: 6, day: 20)
        // Cache up to day 15, cumulative 100 at each entry (all spend on day 1)
        let existingCache = DailyForecastCache(
            monthKey: "2026-06",
            computedUpToDay: 15,
            days: Array(1...15),
            amounts: Array(repeating: 100.0, count: 15)
        )
        // New transaction on day 18: €40
        let transactions = [tx(on: date(year: 2026, month: 6, day: 18), amount: -40)]

        let (_, updatedCache) = service.compute(
            expenseTransactions: transactions, cache: existingCache, now: now
        )

        #expect(updatedCache.computedUpToDay == 20)
        #expect(updatedCache.days.count == 20)
        // days 16, 17, 19, 20 add 0; day 18 adds 40 → final = 140
        #expect(updatedCache.amounts.last == 140.0)
    }

    @Test("month boundary discards old cache and recomputes from day 1")
    func monthBoundaryFullRecompute() {
        let now = date(year: 2026, month: 7, day: 5)
        let juneCache = DailyForecastCache(
            monthKey: "2026-06",
            computedUpToDay: 30,
            days: Array(1...30),
            amounts: Array(1...30).map { Double($0) * 10.0 }
        )
        let transactions = [tx(on: date(year: 2026, month: 7, day: 1), amount: -20)]

        let (_, updatedCache) = service.compute(
            expenseTransactions: transactions, cache: juneCache, now: now
        )

        #expect(updatedCache.monthKey == "2026-07")
        #expect(updatedCache.days.count == 5)
        #expect(updatedCache.amounts[0] == 20.0)  // fresh cumulative from July 1
    }
}
