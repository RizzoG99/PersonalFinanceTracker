//
//  TravelListRefreshTests.swift
//  PersonalFinanceTrakerTests
//
//  A refresh regroups twice — once from `travels`, once from `filteredItems` —
//  and both group off the main thread. These cover the newest result winning.
//

import Testing
import Foundation
@testable import PersonalFinanceTraker

@MainActor
struct TravelListRefreshTests {
    private func makeViewModel(_ repo: MockTransactionRepository) async -> TransactionListViewModel {
        let vm = TransactionListViewModel(repo: repo)
        vm.load()
        await vm.loadTask?.value
        await vm.groupingTask?.value
        return vm
    }

    private func summaries(_ vm: TransactionListViewModel) -> [TravelSummary] {
        vm.groupedItems.flatMap(\.1).compactMap { if case .travel(let s) = $0 { return s } else { return nil } }
    }

    /// Tagging an existing transaction from the edit sheet must collapse it on the *first*
    /// refresh — it used to take a second edit, because the stale grouping landed last.
    @Test func taggingAnExistingTransactionCollapsesOnFirstRefresh() async {
        let travelId = UUID()
        let repo = MockTransactionRepository()
        repo.stubbedTravels = [TravelSnapshot(id: travelId, name: "Barcellona", symbolName: "airplane")]
        repo.stubbedTransactions = [.test(amount: -40, category: "🍽️ Food")]

        // The travel has no members yet, so Activity shows only the transaction.
        let vm = await makeViewModel(repo)
        #expect(vm.groupedItems.flatMap(\.1).count == 1)
        #expect(summaries(vm).isEmpty)

        // What the edit sheet's save amounts to: the transaction now carries the travel.
        repo.stubbedTransactions = [.test(amount: -40, category: "🍽️ Food", travelId: travelId)]
        vm.reload()
        await vm.loadTask?.value
        await vm.groupingTask?.value

        #expect(summaries(vm).first?.count == 1)
        #expect(summaries(vm).first?.total == -40)
        // The member is folded into the travel, not listed beside it.
        #expect(vm.groupedItems.flatMap(\.1).count == 1)
    }

    /// The mirror case: untagging must un-collapse just as promptly.
    @Test func untaggingRestoresThePlainRowOnFirstRefresh() async {
        let travelId = UUID()
        let repo = MockTransactionRepository()
        repo.stubbedTravels = [TravelSnapshot(id: travelId, name: "Barcellona", symbolName: "airplane")]
        repo.stubbedTransactions = [.test(amount: -40, category: "🍽️ Food", travelId: travelId)]

        let vm = await makeViewModel(repo)
        #expect(vm.groupedItems.flatMap(\.1).count == 1)

        repo.stubbedTransactions = [.test(amount: -40, category: "🍽️ Food")]
        vm.reload()
        await vm.loadTask?.value
        await vm.groupingTask?.value

        #expect(summaries(vm).isEmpty)
        #expect(vm.groupedItems.flatMap(\.1).count == 1)
    }
}
