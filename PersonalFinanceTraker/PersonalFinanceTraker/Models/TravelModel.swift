//
//  TravelModel.swift
//  PersonalFinanceTraker
//

import Foundation
import SwiftData

/// A named folder for the expenses of one trip.
///
/// Membership is an explicit `TransactionModel.travelId` tag, mirroring `goalId`.
/// A travel only changes how the Activity list *renders* its members — budgets,
/// insights and the category breakdown still see each expense individually.
@Model
final class TravelModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var symbolName: String
    var createdAt: Date

    // `id` is injectable so a restore can preserve it — transactions reference
    // travels by raw UUID, so a regenerated id would orphan every member.
    init(id: UUID = UUID(), name: String, symbolName: String = "airplane", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.createdAt = createdAt
    }
}

extension TravelModel: Hashable {
    static func == (lhs: TravelModel, rhs: TravelModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
