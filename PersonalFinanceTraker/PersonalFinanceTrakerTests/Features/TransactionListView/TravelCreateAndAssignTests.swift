//
//  TravelCreateAndAssignTests.swift
//  PersonalFinanceTrakerTests
//
//  The travel picker's empty state creates a travel and moves the selection into it in
//  one step. Two writes have to land in order against an id that does not exist until
//  the first one returns, so the ordering is worth pinning down.
//

import Testing
import Foundation
@testable import PersonalFinanceTraker

@MainActor
struct TravelCreateAndAssignTests {
    private func makeViewModel(_ repo: MockTransactionRepository) async -> TransactionListViewModel {
        let vm = TransactionListViewModel(repo: repo)
        vm.load()
        await vm.loadTask?.value
        await vm.groupingTask?.value
        return vm
    }

    /// The whole point of the fix: one gesture creates the travel *and* tags everything
    /// that was selected, so the user never has to reopen the picker.
    @Test func creatingFromThePickerTagsTheSelection() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [
            .test(amount: -40, category: "🍽️ Food"),
            .test(amount: -12, category: "☕ Coffee & Drinks"),
        ]

        let vm = await makeViewModel(repo)
        let selected = vm.filteredItems.map(\.id)
        vm.isSelecting = true
        selected.forEach { vm.toggleSelection($0) }

        vm.addTravelAndAssignSelection(name: "Roma", symbolName: "airplane")
        await vm.bulkEditTask?.value

        // The travel exists...
        #expect(repo.stubbedTravels.count == 1)
        #expect(repo.stubbedTravels.first?.name == "Roma")
        #expect(repo.stubbedTravels.first?.symbolName == "airplane")

        // ...and the selection was tagged with *that* travel's id, not nil and not a
        // second one created along the way.
        #expect(repo.setTravelCalls.count == 1)
        #expect(repo.setTravelCalls.first?.0 == repo.stubbedTravels.first?.id)
        #expect(Set(repo.setTravelCalls.first?.1 ?? []) == Set(selected))
    }

    /// Selection mode ends on the way out, like every other bulk action — the action bar
    /// must not be left hanging over a list that has already moved on.
    @Test func creatingFromThePickerExitsSelection() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [.test(amount: -40, category: "🍽️ Food")]

        let vm = await makeViewModel(repo)
        vm.isSelecting = true
        vm.toggleSelection(vm.filteredItems[0].id)

        vm.addTravelAndAssignSelection(name: "Roma", symbolName: "airplane")
        await vm.bulkEditTask?.value

        #expect(!vm.isSelecting)
        #expect(vm.selectedIDs.isEmpty)
    }

    /// "Remove from travel" is destructive-looking and does nothing when none of the
    /// selected rows are in a travel, so the picker only offers it when it would act.
    @Test func untaggingIsOnlyOfferedWhenSomethingIsTagged() async throws {
        let repo = MockTransactionRepository()
        let trip = UUID()
        repo.stubbedTransactions = [
            .test(amount: -40, category: "🍽️ Food"),
            .test(amount: -12, category: "☕ Coffee & Drinks", travelId: trip),
        ]

        let vm = await makeViewModel(repo)
        vm.isSelecting = true

        let untagged = try #require(vm.filteredItems.first { $0.travelId == nil })
        let tagged = try #require(vm.filteredItems.first { $0.travelId != nil })

        vm.toggleSelection(untagged.id)
        #expect(!vm.selectionHasTravel)

        // One tagged row in the selection is enough — that row has somewhere to be pulled
        // out of, whatever else is selected alongside it.
        vm.toggleSelection(tagged.id)
        #expect(vm.selectionHasTravel)
    }

    /// Nothing selected must create nothing. The picker's Add button is reachable from the
    /// toolbar too, and an empty selection there would otherwise leave a stray travel.
    @Test func creatingWithAnEmptySelectionDoesNothing() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [.test(amount: -40, category: "🍽️ Food")]

        let vm = await makeViewModel(repo)
        vm.isSelecting = true

        vm.addTravelAndAssignSelection(name: "Roma", symbolName: "airplane")
        await vm.bulkEditTask?.value

        #expect(repo.stubbedTravels.isEmpty)
        #expect(repo.setTravelCalls.isEmpty)
    }
}
