import Testing
import Foundation
@testable import PersonalFinanceTraker

struct TravelGroupingTests {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func travel(_ id: UUID, createdAt: Date = Date()) -> TravelSnapshot {
        TravelSnapshot(id: id, name: "Barcellona Travel", symbolName: "airplane", createdAt: createdAt)
    }

    private func rows(_ sections: [(String, [ActivityRow])]) -> [ActivityRow] {
        sections.flatMap(\.1)
    }

    private func summaries(_ sections: [(String, [ActivityRow])]) -> [TravelSummary] {
        rows(sections).compactMap { if case .travel(let s) = $0 { return s } else { return nil } }
    }

    @Test func withoutTravelsEveryRowIsATransaction() {
        let items = [
            TransactionSnapshot.test(timestamp: date(2026, 6, 1), amount: -10, category: "🍽️ Food"),
            TransactionSnapshot.test(timestamp: date(2026, 6, 2), amount: -20, category: "🍽️ Food"),
        ]

        let sections = ActivityRowGrouper.group(items)

        #expect(sections.count == 2)
        #expect(rows(sections).allSatisfy { $0.transaction != nil })
    }

    // The trip rides at the top while travelling, then settles where the trip ended.
    @Test func travelAnchorsToItsMostRecentMember() {
        let id = UUID()
        let items = [
            TransactionSnapshot.test(timestamp: date(2026, 6, 1), amount: -100, category: "🏨 Hotel", travelId: id),
            TransactionSnapshot.test(timestamp: date(2026, 6, 5), amount: -300, category: "✈️ Flights", travelId: id),
        ]

        let sections = ActivityRowGrouper.group(items, travels: [travel(id)])

        #expect(sections.count == 1)
        let summary = try! #require(summaries(sections).first)
        #expect(summary.anchorDate == date(2026, 6, 5))
        #expect(summary.count == 2)
    }

    @Test func membersDoNotAlsoAppearIndividually() {
        let id = UUID()
        let items = [
            TransactionSnapshot.test(timestamp: date(2026, 6, 1), amount: -100, category: "🏨 Hotel", travelId: id),
            TransactionSnapshot.test(timestamp: date(2026, 6, 2), amount: -40, category: "🛒 Groceries"),
        ]

        let sections = ActivityRowGrouper.group(items, travels: [travel(id)])

        let loose = rows(sections).compactMap(\.transaction)
        #expect(loose.count == 1)
        #expect(loose[0].category == "🛒 Groceries")
        #expect(summaries(sections).count == 1)
    }

    // Callers opt out of collapsing by passing no travels — this is the search /
    // filter / multi-select path, and it must leave every member visible.
    @Test func passingNoTravelsLeavesMembersUncollapsed() {
        let id = UUID()
        let items = [
            TransactionSnapshot.test(timestamp: date(2026, 6, 1), amount: -100, category: "🏨 Hotel", travelId: id),
            TransactionSnapshot.test(timestamp: date(2026, 6, 5), amount: -300, category: "✈️ Flights", travelId: id),
        ]

        let sections = ActivityRowGrouper.group(items, travels: [])

        #expect(rows(sections).count == 2)
        #expect(summaries(sections).isEmpty)
    }

    // A friend paying you back is a positive amount inside the trip.
    @Test func totalSumsSignedAmountsSoRefundsReduceIt() {
        let id = UUID()
        let items = [
            TransactionSnapshot.test(timestamp: date(2026, 6, 1), amount: -400, category: "🏨 Hotel", travelId: id),
            TransactionSnapshot.test(timestamp: date(2026, 6, 2), amount: 50, category: "💸 Refund", travelId: id),
        ]

        let sections = ActivityRowGrouper.group(items, travels: [travel(id)])

        #expect(summaries(sections).first?.total == -350)
    }

    @Test func emptyTravelStillGetsARowAtZero() {
        let id = UUID()
        let sections = ActivityRowGrouper.group([], travels: [travel(id, createdAt: date(2026, 6, 3))])

        let summary = try! #require(summaries(sections).first)
        #expect(summary.total == 0)
        #expect(summary.count == 0)
        #expect(summary.anchorDate == date(2026, 6, 3))
    }

    // A tag pointing at a travel that no longer exists must not swallow the row.
    @Test func memberOfMissingTravelFallsBackToAPlainRow() {
        let items = [
            TransactionSnapshot.test(timestamp: date(2026, 6, 1), amount: -100, category: "🏨 Hotel", travelId: UUID())
        ]

        let sections = ActivityRowGrouper.group(items, travels: [])

        #expect(rows(sections).compactMap(\.transaction).count == 1)
    }

    @Test func sectionsAreOrderedNewestFirst() {
        let id = UUID()
        let items = [
            TransactionSnapshot.test(timestamp: date(2026, 6, 1), amount: -10, category: "🛒 Groceries"),
            TransactionSnapshot.test(timestamp: date(2026, 6, 9), amount: -100, category: "🏨 Hotel", travelId: id),
            TransactionSnapshot.test(timestamp: date(2026, 6, 5), amount: -20, category: "🛒 Groceries"),
        ]

        let sections = ActivityRowGrouper.group(items, travels: [travel(id)])

        let anchors = sections.map { $0.1.first!.anchorDate }
        #expect(anchors == anchors.sorted(by: >))
        // The travel, anchored to 6-9, leads.
        #expect(sections.first?.1.first.map { if case .travel = $0 { true } else { false } } == true)
    }
}
