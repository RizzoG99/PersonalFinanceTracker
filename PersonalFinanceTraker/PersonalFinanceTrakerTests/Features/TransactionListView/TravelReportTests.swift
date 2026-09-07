import Testing
import Foundation
@testable import PersonalFinanceTraker

struct TravelReportTests {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func expense(_ amount: Decimal, _ category: String, _ day: Int) -> TransactionSnapshot {
        .test(timestamp: date(2026, 6, day), amount: amount, category: category)
    }

    @Test func emptyTripReportsNothingRatherThanDividingByZero() {
        let report = TravelReport(members: [])

        #expect(report.count == 0)
        #expect(report.dayCount == 0)
        #expect(report.perDay == 0)
        #expect(report.startDate == nil)
        #expect(report.categories.isEmpty)
    }

    @Test func spentIgnoresSignAndNetKeepsIt() {
        let report = TravelReport(members: [
            expense(-250, "🏨 Hotel", 1),
            expense(-150, "✈️ Flights", 2),
            expense(50, "💸 Refund", 3),
        ])

        #expect(report.spent == 400)
        #expect(report.refunded == 50)
        #expect(report.net == -350)
    }

    // A trip that starts and ends the same day lasted one day, not zero.
    @Test func singleDayTripSpansOneDay() {
        let report = TravelReport(members: [
            expense(-60, "🍽️ Food", 4),
            expense(-40, "🚕 Taxi", 4),
        ])

        #expect(report.dayCount == 1)
        #expect(report.perDay == 100)
    }

    @Test func dayCountIsInclusiveOfBothEnds() {
        // 1 June → 5 June is five days, not four.
        let report = TravelReport(members: [
            expense(-100, "🏨 Hotel", 1),
            expense(-400, "🍽️ Food", 5),
        ])

        #expect(report.dayCount == 5)
        #expect(report.perDay == 100)
        #expect(report.startDate == date(2026, 6, 1))
        #expect(report.endDate == date(2026, 6, 5))
    }

    @Test func categoriesAreExpensesOnlyBiggestFirst() {
        let report = TravelReport(members: [
            expense(-100, "🍽️ Food", 1),
            expense(-250, "🏨 Hotel", 2),
            expense(-50, "🍽️ Food", 3),
            expense(80, "💸 Refund", 4),
        ])

        #expect(report.categories.map(\.category) == ["🏨 Hotel", "🍽️ Food"])
        #expect(report.categories.map(\.amount) == [250, 150])
        // A refund is not a category the trip "spent" on.
        #expect(report.categories.contains { $0.category == "💸 Refund" } == false)
    }

    @Test func perDayUsesSpendingNotNet() {
        // The refund reduces net, but the trip still cost 400 across 2 days of spending.
        let report = TravelReport(members: [
            expense(-200, "🏨 Hotel", 1),
            expense(-200, "🍽️ Food", 2),
            expense(100, "💸 Refund", 2),
        ])

        #expect(report.perDay == 200)
        #expect(report.net == -300)
    }
}
