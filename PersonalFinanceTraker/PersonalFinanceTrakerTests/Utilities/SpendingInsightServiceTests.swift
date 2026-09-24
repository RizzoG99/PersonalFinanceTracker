import Testing
import Foundation
@testable import PersonalFinanceTraker

@Suite("SpendingInsightService")
struct SpendingInsightServiceTests {

    private func makeService() -> SpendingInsightService {
        SpendingInsightService(currencyService: CurrencyService(), pieDataService: PieChartDataService())
    }

    // Returns a date that lands on a specific weekday (1=Sun, 7=Sat) within the last 30 days
    private func dateOnWeekday(_ weekday: Int, weeksAgo: Int = 0) -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        components.weekday = weekday
        components.weekOfYear = (components.weekOfYear ?? 0) - weeksAgo
        return cal.date(from: components) ?? Date()
    }

    private func makeExpense(amount: Decimal, category: String = "🛒 Groceries", on date: Date) -> TransactionSnapshot {
        .test(timestamp: date, amount: -abs(amount), category: category)
    }

    // Returns a Date in a specific calendar week, offset from current week
    private func dateInWeek(weeksAgo: Int, weekday: Int = 3) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekOfYear = (comps.weekOfYear ?? 0) - weeksAgo
        comps.weekday = weekday
        return cal.date(from: comps) ?? Date()
    }

    @Test("4-week streak emits streak observation with 'over a month' detail")
    func fourWeekStreakEmitsObservation() {
        let service = makeService()
        // One transaction per week for 4 consecutive weeks in same category
        let txns = (0..<4).map { makeExpense(amount: 20, category: "🛒 Groceries", on: dateInWeek(weeksAgo: $0)) }
        let obs = service.habitObservations(expenseTransactions: txns)
        // Compared against the same localized lookups SpendingInsightService uses rather than
        // hardcoded English literals, so this doesn't depend on the test device's language.
        let expectedTitle = String(localized: "\("Groceries".localizedCategoryDisplay) — \(4)-week streak")
        let streak = obs.first { $0.title == expectedTitle }
        #expect(streak != nil)
        #expect(streak?.detail == String(localized: "Every week for over a month"))
    }

    @Test("weekend-heavy: emits calendar.badge.clock observation")
    func weekendHeavySpending() {
        let service = makeService()
        // 5 weekend transactions × €50 = €250 total weekend, avg €25/day (€250/10)
        // 5 weekday transactions × €10 = €50 total weekday, avg €2.5/day (€50/20)
        // ratio = 10× — well above 1.3 threshold
        let weekend = (0..<5).map { makeExpense(amount: 50, on: dateOnWeekday(7, weeksAgo: $0 % 4)) }
        let weekday = (0..<5).map { makeExpense(amount: 10, on: dateOnWeekday(2, weeksAgo: $0 % 4)) }
        let obs = service.habitObservations(expenseTransactions: weekend + weekday)
        #expect(obs.contains { $0.sfSymbol == "calendar.badge.clock" })
    }

    @Test("fewer than 5 expenses: no weekend/weekday observation")
    func tooFewExpensesSkipsWeekendWeekday() {
        let service = makeService()
        let txns = (0..<4).map { makeExpense(amount: 50, on: dateOnWeekday(7, weeksAgo: $0)) }
        let obs = service.habitObservations(expenseTransactions: txns)
        #expect(!obs.contains { $0.sfSymbol == "calendar.badge.clock" || $0.sfSymbol == "briefcase" })
    }

    @Test("2-week streak emits no streak observation")
    func twoWeekStreakTooShort() {
        let service = makeService()
        let txns = (0..<2).map { makeExpense(amount: 20, category: "🛒 Groceries", on: dateInWeek(weeksAgo: $0)) }
        let obs = service.habitObservations(expenseTransactions: txns)
        #expect(!obs.contains { $0.title.contains("streak") })
    }

    @Test("at most 2 streak observations emitted")
    func atMostTwoStreaks() {
        let service = makeService()
        // 3 categories each with 4-week streaks
        let cats = ["🛒 Groceries", "🍽️ Restaurants", "⛽ Gas"]
        let txns = cats.flatMap { cat in
            (0..<4).map { makeExpense(amount: 20, category: cat, on: dateInWeek(weeksAgo: $0)) }
        }
        let obs = service.habitObservations(expenseTransactions: txns)
        #expect(obs.filter { $0.title.contains("streak") }.count <= 2)
    }

    @Test("trivial amounts: no weekend/weekday observation despite ratio ≥ 1.3")
    func trivialAmountsSkipWeekendWeekday() {
        let service = makeService()
        // weekend avg = €15/10 = €1.5/day, weekday avg = €10/20 = €0.5/day — ratio = 3× but both trivial
        let weekend = (0..<5).map { makeExpense(amount: 3, on: dateOnWeekday(7, weeksAgo: $0 % 4)) }
        let weekday = (0..<5).map { makeExpense(amount: 2, on: dateOnWeekday(2, weeksAgo: $0 % 4)) }
        let obs = service.habitObservations(expenseTransactions: weekend + weekday)
        #expect(!obs.contains { $0.sfSymbol == "calendar.badge.clock" || $0.sfSymbol == "briefcase" })
    }

    /// Regression guard: categoryTrends used to compare "this month" against itself (the `.month`
    /// filter ignored `referenceDate`), so every row showed a flat "0%" change no matter what
    /// actually happened last month.
    @Test("categoryTrends reports a non-zero change when last month differs from this month")
    func categoryTrendsComputesRealDelta() {
        let service = makeService()
        let calendar = Calendar.current
        let lastMonthRef = calendar.date(byAdding: .month, value: -1, to: .now)!

        let txns = [
            makeExpense(amount: 100, category: "🛒 Groceries", on: .now),
            makeExpense(amount: 50, category: "🛒 Groceries", on: lastMonthRef)
        ]

        let trends = service.categoryTrends(expenseTransactions: txns)
        let groceries = trends.first { $0.category.category == "🛒 Groceries" }
        #expect(groceries?.changePercent != 0)
        #expect(groceries?.direction == .up)
    }

    /// Regression guard: heroInsight kept using plain calendar-month boundaries even after
    /// categoryTrends was fixed to be pay-cycle-aware, so the two insights on the same screen
    /// could silently disagree about what "this month" means for anyone with a non-default
    /// pay-cycle start day.
    @Test("heroInsight uses the pay-cycle month, not the calendar month")
    func heroInsightRespectsPayCycleStartDay() {
        let calendar = Calendar.current
        let now = Date.now
        let todayDay = calendar.component(.day, from: now)
        // Needs today comfortably before the chosen start day, so "now" falls in a financial
        // month that began last calendar month — skip near month-end, where that can't be
        // constructed with a valid (1-28) start day.
        guard todayDay < 27 else { return }
        let startDay = todayDay + 1

        let financialStart = PayCycleService.financialMonthStart(for: now, startDay: startDay, calendar: calendar)
        // A day into the financial month, but still inside the *previous* calendar month: plain
        // calendar-month logic would file this as "last month"; pay-cycle-aware logic must file
        // it as "current".
        let probeDate = calendar.date(byAdding: .day, value: 1, to: financialStart) ?? financialStart
        let service = makeService()
        let txns = [makeExpense(amount: 40, on: probeDate)]

        let insight = service.heroInsight(expenseTransactions: txns, payCycleStartDay: startDay)
        // Correctly classified as current-period spend with no prior period to compare against,
        // this hits the existing "not enough history" guard (lastTotal == 0) and returns the
        // placeholder. Misclassified as *last* month instead, currentTotal would be 0 and
        // lastTotal > 0, producing a spurious "100% less" reading — that's the bug this guards.
        #expect(insight.title == String(localized: "Building your picture"))
        #expect(insight.trendDirection == .flat)
    }

    @Test("weekday-heavy: emits briefcase observation")
    func weekdayHeavySpending() {
        let service = makeService()
        // 5 weekday transactions × €50 = €250 total weekday, avg €12.5/day (€250/20)
        // 5 weekend transactions × €10 = €50 total weekend, avg €5/day (€50/10)
        // inverse ratio = 2.5× — well above 1.3 threshold
        let weekday = (0..<5).map { makeExpense(amount: 50, on: dateOnWeekday(2, weeksAgo: $0 % 4)) }
        let weekend = (0..<5).map { makeExpense(amount: 10, on: dateOnWeekday(7, weeksAgo: $0 % 4)) }
        let obs = service.habitObservations(expenseTransactions: weekday + weekend)
        #expect(obs.contains { $0.sfSymbol == "briefcase" })
    }

    // Fixed, DST-boundary-free calendar dates (April follows March, both regular-length months)
    // so heroInsight's elapsed-time-interval cutoff and calendar-day offsets line up exactly.
    private func fixedDate(day: Int, month: Int = 4, year: Int = 2024) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// #154: identical daily pace in both months used to read as "spending 33% less" because
    /// current-month-to-date (19 days) was compared against a *complete* last month (31 days).
    /// The days-21/26 last-month expenses land *after* the elapsed cutoff (March 20) — the old,
    /// uncapped code counted them (lastTotal 300 vs currentTotal 200 → "33% less"); the fix must
    /// drop them so both sides cover the same 19 days and read flat. (March 21/26 avoid the
    /// March-2024 US/EU DST boundaries around the 10th/31st, which would shift a day-20 cutoff.)
    @Test("heroInsight: identical pace across a partial vs full month reads as flat, not a false decline")
    func heroInsightFlatWhenPaceMatchesAcrossPartialMonth() {
        let service = makeService()
        let referenceDate = fixedDate(day: 20) // 19 days into April — well past the early-month guard
        let currentMonth = [1, 6, 11, 16].map { makeExpense(amount: 50, on: fixedDate(day: $0)) }
        let lastMonth = [1, 6, 11, 16, 21, 26].map { makeExpense(amount: 50, on: fixedDate(day: $0, month: 3)) }

        let insight = service.heroInsight(expenseTransactions: currentMonth + lastMonth, referenceDate: referenceDate)
        #expect(insight.trendDirection == .flat)
        #expect(insight.title == String(localized: "On track this month"))
    }

    /// #154: a future-dated transaction (e.g. a materialized recurring rule later this month)
    /// must not widen `currentTotal` beyond `referenceDate` — that would reintroduce the same
    /// asymmetric-window bias in the opposite direction ("spending more" that hasn't happened yet).
    @Test("heroInsight: a transaction dated after referenceDate is excluded from the current total")
    func heroInsightExcludesFutureDatedTransactions() {
        let service = makeService()
        let referenceDate = fixedDate(day: 20)
        let currentMonth = [makeExpense(amount: 50, on: fixedDate(day: 10))]
        let futureDated = [makeExpense(amount: 5000, on: fixedDate(day: 25))] // after referenceDate
        let lastMonth = [makeExpense(amount: 50, on: fixedDate(day: 10, month: 3))]

        let insight = service.heroInsight(expenseTransactions: currentMonth + futureDated + lastMonth, referenceDate: referenceDate)
        #expect(insight.trendDirection == .flat)
        #expect(insight.title == String(localized: "On track this month"))
    }

    /// A genuine pace difference (half the spend) must still surface as `.down` — the fix
    /// should stop the false signal without muting a real one.
    @Test("heroInsight: a real pace drop still reads as down")
    func heroInsightStillDetectsRealDecline() {
        let service = makeService()
        let referenceDate = fixedDate(day: 20)
        let currentMonth = [makeExpense(amount: 100, on: fixedDate(day: 10))]
        let lastMonth = [makeExpense(amount: 200, on: fixedDate(day: 10, month: 3))]

        let insight = service.heroInsight(expenseTransactions: currentMonth + lastMonth, referenceDate: referenceDate)
        #expect(insight.trendDirection == .down)
    }

    /// #154 edge case: very early in the month, both windows shrink to almost nothing and a
    /// single transaction can otherwise swing the % wildly (e.g. "Spending 1500% more").
    @Test("heroInsight: early-month noise stays flat instead of a wild swing")
    func heroInsightStaysFlatInFirstFewDaysOfMonth() {
        let service = makeService()
        let referenceDate = fixedDate(day: 2) // 1 day elapsed — under the 7-day floor
        let currentMonth = [makeExpense(amount: 500, on: fixedDate(day: 1))]
        let lastMonth = [makeExpense(amount: 5, on: fixedDate(day: 1, month: 3))]

        let insight = service.heroInsight(expenseTransactions: currentMonth + lastMonth, referenceDate: referenceDate)
        #expect(insight.trendDirection == .flat)
        // "Building your picture", not "similar to last month" — this branch hasn't evaluated
        // pace at all, so it shouldn't claim to.
        #expect(insight.title == String(localized: "Building your picture"))
    }

    /// #154: categoryTrends has the identical partial-vs-full bias as heroInsight, on the same
    /// screen — identical pace per category must not read as a decline. The March 21/26 expenses
    /// land after the elapsed cutoff; the old, uncapped `last` window counted them (300 vs 200 →
    /// "down"), so this fails against the old code and passes only once both sides are capped.
    @Test("categoryTrends: identical pace across a partial vs full month reads as flat")
    func categoryTrendsFlatWhenPaceMatchesAcrossPartialMonth() {
        let service = makeService()
        let referenceDate = fixedDate(day: 20)
        let currentMonth = [1, 6, 11, 16].map { makeExpense(amount: 50, category: "🛒 Groceries", on: fixedDate(day: $0)) }
        let lastMonth = [1, 6, 11, 16, 21, 26].map { makeExpense(amount: 50, category: "🛒 Groceries", on: fixedDate(day: $0, month: 3)) }

        let trends = service.categoryTrends(expenseTransactions: currentMonth + lastMonth, referenceDate: referenceDate)
        let groceries = trends.first { $0.category.category == "🛒 Groceries" }
        #expect(groceries?.direction == .flat)
    }

    /// #154: same future-dated-transaction hole as heroInsight — a materialized recurring rule
    /// later this month must not inflate the current-month pie beyond `referenceDate`.
    @Test("categoryTrends: a transaction dated after referenceDate is excluded from the current pie")
    func categoryTrendsExcludesFutureDatedTransactions() {
        let service = makeService()
        let referenceDate = fixedDate(day: 20)
        let currentMonth = [makeExpense(amount: 50, category: "🛒 Groceries", on: fixedDate(day: 10))]
        let futureDated = [makeExpense(amount: 5000, category: "🛒 Groceries", on: fixedDate(day: 25))]
        let lastMonth = [makeExpense(amount: 50, category: "🛒 Groceries", on: fixedDate(day: 10, month: 3))]

        let trends = service.categoryTrends(expenseTransactions: currentMonth + futureDated + lastMonth, referenceDate: referenceDate)
        let groceries = trends.first { $0.category.category == "🛒 Groceries" }
        #expect(groceries?.direction == .flat)
    }
}
