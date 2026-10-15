//
//  GoalProjectionTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

@MainActor
struct GoalProjectionTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// Fixed "today": Oct 10, 2026.
    private var now: Date { date(2026, 10, 10) }

    private func project(
        target: Decimal,
        saved: Decimal,
        deadline: Date? = nil,
        createdAt: Date? = nil,
        planned: Decimal = 0,
        transfers: [(date: Date, amount: Decimal)] = []
    ) -> GoalProjection {
        let goal = GoalSnapshot.test(name: "Goal", targetAmount: target, deadline: deadline, createdAt: createdAt ?? date(2026, 1, 1))
        return GoalProjection.make(
            goal: goal, saved: saved, plannedMonthly: planned, transfers: transfers, now: now, calendar: calendar
        )
    }

    @Test func plannedPaceWinsOverRecentTransfers() {
        let projection = project(
            target: 3000, saved: 1800, planned: 200,
            transfers: [(date(2026, 9, 5), -150), (date(2026, 8, 5), -150), (date(2026, 7, 15), -150)]
        )
        #expect(projection.source == .planned)
        #expect(projection.monthlyPace == 200)
        // €1,200 left at €200 → 6 payments: Oct, Nov, Dec, Jan, Feb, Mar.
        #expect(projection.state == .eta(date(2027, 3, 1).startOfMonth(calendar)))
    }

    @Test func recentPaceAveragesTheLastThreeMonths() {
        let projection = project(
            target: 1500, saved: 750,
            transfers: [(date(2026, 10, 5), -150), (date(2026, 9, 5), -150), (date(2026, 8, 5), -150), (date(2026, 3, 1), -300)]
        )
        #expect(projection.source == .recent)
        #expect(projection.monthlyPace == 150) // the March transfer is outside the window
    }

    @Test func youngGoalIsNotDilutedByTheFullWindow() {
        let projection = project(
            target: 1000, saved: 200, createdAt: date(2026, 9, 10),
            transfers: [(date(2026, 9, 12), -200)]
        )
        #expect(projection.monthlyPace == 200)
    }

    @Test func deadlineMonthsIncludeTheCurrentMonth() {
        // Oct 10 → Dec 31 leaves Oct, Nov, Dec: €900 / 3 = €300.
        let projection = project(target: 900, saved: 0, deadline: date(2026, 12, 31))
        #expect(projection.state == .needsContribution(required: 300, deadline: date(2026, 12, 31)))
    }

    @Test func behindRoundsTheRequiredAmountUp() {
        // €2,000 left, Oct → Apr = 7 months → €285.71 → €286; €220/month needs 10.
        let deadline = date(2027, 4, 10)
        let projection = project(target: 3000, saved: 1000, deadline: deadline, planned: 220)
        #expect(projection.state == .behind(required: 286, deadline: deadline))
    }

    @Test func onTrackWhenThePaceFitsTheDeadline() {
        let deadline = date(2026, 12, 9)
        let projection = project(target: 500, saved: 300, deadline: deadline, planned: 100)
        #expect(projection.state == .onTrack(eta: date(2026, 11, 1).startOfMonth(calendar), deadline: deadline))
    }

    @Test func etaAndRequiredAgreeOnTheBoundary() {
        // €600 at €200 = 3 payments, exactly the months left to Dec: on track, not behind.
        let deadline = date(2026, 12, 1)
        let projection = project(target: 600, saved: 0, deadline: deadline, planned: 200)
        #expect(projection.state == .onTrack(eta: date(2026, 12, 1).startOfMonth(calendar), deadline: deadline))
    }

    @Test func zeroPaceWithoutDeadlineInvitesAContribution() {
        let projection = project(target: 800, saved: 0)
        #expect(projection.state == .needsContribution(required: nil, deadline: nil))
        #expect(projection.paceCaption == nil)
    }

    @Test func deadlinePassedKeepsTheETA() {
        let projection = project(
            target: 2000, saved: 300, deadline: date(2026, 9, 10), createdAt: date(2026, 7, 10),
            transfers: [(date(2026, 10, 5), -100), (date(2026, 9, 5), -100), (date(2026, 8, 5), -100)]
        )
        // 3 months of €100 → €1,700 left → 17 payments → Feb 2028.
        #expect(projection.state == .deadlinePassed(eta: date(2028, 2, 1).startOfMonth(calendar)))
    }

    @Test func deadlinePassedWithNothingGoingIn() {
        let projection = project(target: 2000, saved: 300, deadline: date(2026, 9, 10))
        #expect(projection.state == .deadlinePassed(eta: nil))
    }

    @Test func reachedGoalIsComplete() {
        let projection = project(target: 400, saved: 450, planned: 100)
        #expect(projection.state == .complete)
        #expect(projection.sentence == nil)
    }

    @Test(arguments: [
        (RecurrenceFrequency.monthly, 1, Decimal(-200), Decimal(-200)),
        (.monthly, 2, -200, -100),
        (.weekly, 1, -12, -52),
        (.yearly, 1, -1200, -100),
    ])
    func monthlyEquivalent(frequency: RecurrenceFrequency, interval: Int, amount: Decimal, expected: Decimal) {
        let rule = RecurrenceRuleSnapshot.test(
            frequency: frequency, interval: interval, startDate: now, amount: amount, category: "→ Goal"
        )
        #expect(rule.monthlyEquivalent == expected)
    }
}

private extension Date {
    func startOfMonth(_ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: self)!.start
    }
}
