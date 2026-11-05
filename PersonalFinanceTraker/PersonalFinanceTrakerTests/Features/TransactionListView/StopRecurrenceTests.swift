import Foundation
import SwiftUI
import Testing
@testable import PersonalFinanceTraker

@MainActor
struct StopRecurrenceTests {
    private final class Box { var ids: Set<UUID> = [] }

    private let box = Box()
    private let repo = MockTransactionRepository()
    private let rule = RecurrenceRuleSnapshot.test(startDate: .now, amount: -10, category: "Gym")

    private var binding: Binding<Set<UUID>> {
        let box = box
        return Binding(get: { box.ids }, set: { box.ids = $0 })
    }

    @Test func hidesTheRuleBeforeAnySuspension() async {
        let task = stopRecurrence(rule, stoppedIDs: binding, repo: repo)
        #expect(box.ids.contains(rule.id))
        await task.value
    }

    @Test func keepsTheRuleHiddenAfterASuccessfulSave() async {
        await stopRecurrence(rule, stoppedIDs: binding, repo: repo).value
        #expect(repo.closeRecurrenceRuleCalls.map(\.id) == [rule.id])
        #expect(box.ids.contains(rule.id))
    }

    @Test func bringsTheRuleBackWhenTheSaveFails() async {
        repo.shouldThrow = true
        await stopRecurrence(rule, stoppedIDs: binding, repo: repo).value
        #expect(box.ids.isEmpty)
    }
}
