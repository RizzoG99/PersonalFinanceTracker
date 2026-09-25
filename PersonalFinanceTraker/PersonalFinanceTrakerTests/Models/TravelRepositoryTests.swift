import Testing
import Foundation
import SwiftData
@testable import PersonalFinanceTraker

struct TravelRepositoryTests {
    private func makeActor() -> TransactionActor {
        let schema = Schema([TransactionModel.self, CategoryModel.self, RecurrenceRule.self, TravelModel.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return TransactionActor(modelContainer: container)
    }

    private func expense(_ amount: Decimal, _ note: String, travelId: UUID?) -> TransactionInput {
        TransactionInput(
            timestamp: Date(),
            amount: amount,
            note: note,
            category: "🍽️ Food",
            currencyCode: "EUR",
            travelId: travelId
        )
    }

    @Test func addedTravelIsFetchedBack() async throws {
        let actor = makeActor()
        let id = try await actor.addTravel(name: "Barcellona Travel", symbolName: "airplane")

        let travels = try await actor.fetchTravels()
        #expect(travels.count == 1)
        #expect(travels[0].id == id)
        #expect(travels[0].name == "Barcellona Travel")
    }

    @Test func taggedTransactionsCarryTheTravelId() async throws {
        let actor = makeActor()
        let id = try await actor.addTravel(name: "Barcellona Travel", symbolName: "airplane")

        try await actor.add(expense(-250, "Hotel", travelId: id))
        try await actor.add(expense(-150, "Flights", travelId: id))
        try await actor.add(expense(-40, "Groceries", travelId: nil))

        let all = try await actor.fetchAll()
        let members = all.filter { $0.travelId == id }
        #expect(members.count == 2)
        #expect(members.reduce(Decimal(0)) { $0 + $1.amount } == -400)
    }

    // The folder is deletable; the money inside it is not. This is the one
    // destructive path in the feature, so it gets the explicit check.
    @Test func deletingTravelUntagsMembersButKeepsThem() async throws {
        let actor = makeActor()
        let id = try await actor.addTravel(name: "Barcellona Travel", symbolName: "airplane")
        try await actor.add(expense(-250, "Hotel", travelId: id))
        try await actor.add(expense(-150, "Flights", travelId: id))

        try await actor.deleteTravel(id: id)

        #expect(try await actor.fetchTravels().isEmpty)
        let all = try await actor.fetchAll()
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.travelId == nil })
    }

    @Test func setTravelBulkTagsAndUntags() async throws {
        let actor = makeActor()
        let id = try await actor.addTravel(name: "Barcellona Travel", symbolName: "airplane")
        try await actor.add(expense(-250, "Hotel", travelId: nil))
        try await actor.add(expense(-150, "Flights", travelId: nil))

        let ids = try await actor.fetchAll().map(\.id)
        try await actor.setTravel(id, forIDs: ids)
        #expect(try await actor.fetchAll().allSatisfy { $0.travelId == id })

        try await actor.setTravel(nil, forIDs: ids)
        #expect(try await actor.fetchAll().allSatisfy { $0.travelId == nil })
    }

    // Restore rebuilds travels from a backup; regenerating ids here would orphan
    // every member, since transactions reference travels by raw UUID.
    @Test func replaceAllTravelsPreservesIds() async throws {
        let actor = makeActor()
        let id = UUID()
        try await actor.replaceAllTravels([
            TravelSnapshot(id: id, name: "Barcellona Travel", symbolName: "airplane")
        ])

        let travels = try await actor.fetchTravels()
        #expect(travels.count == 1)
        #expect(travels[0].id == id)
    }
}
