import Foundation
import SwiftData

@Model
final class RecurrenceRule {
    @Attribute(.unique) var id: UUID
    var frequency: String // RecurrenceFrequency raw value — see CategoryModel.type for the same pattern
    var interval: Int
    var startDate: Date
    var endDate: Date?              // nil = open-ended / active
    var lastMaterializedDate: Date? // catch-up cursor; nil = never materialized

    // Transaction template — mirrors TransactionInput
    var amount: Decimal
    var note: String
    var category: String
    var currencyCode: String
    var goalId: UUID?

    @Relationship(deleteRule: .nullify)
    var categoryModel: CategoryModel?

    init(
        id: UUID = UUID(),
        frequency: RecurrenceFrequency,
        interval: Int,
        startDate: Date,
        endDate: Date? = nil,
        lastMaterializedDate: Date? = nil,
        amount: Decimal,
        note: String,
        category: String,
        currencyCode: String,
        goalId: UUID? = nil,
        categoryModel: CategoryModel? = nil
    ) {
        self.id = id
        self.frequency = frequency.rawValue
        self.interval = interval
        self.startDate = startDate
        self.endDate = endDate
        self.lastMaterializedDate = lastMaterializedDate
        self.amount = amount
        self.note = note
        self.category = category
        self.currencyCode = currencyCode
        self.goalId = goalId
        self.categoryModel = categoryModel
    }

    var recurrenceFrequency: RecurrenceFrequency {
        RecurrenceFrequency(rawValue: frequency) ?? .monthly
    }

    func isActive(asOf date: Date) -> Bool {
        endDate == nil || endDate! >= date
    }
}
