//
//  Item.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import Foundation
import SwiftData

@Model
public final class TransactionModel {
    var timestamp: Date
    var amount: Decimal
    var note: String
    var category: String
    var idCategory: String?
    var currencyCode: String = "EUR"
    var goalId: UUID?

    @Relationship(deleteRule: .nullify)
    var categoryModel: CategoryModel?

    init(timestamp: Date,
         amount: Decimal,
         note: String,
         category: String,
         idCategory: String? = nil,
         categoryModel: CategoryModel? = nil,
         currencyCode: String = "EUR",
         goalId: UUID? = nil) {
        self.timestamp = timestamp
        self.amount = amount
        self.note = note
        self.category = category
        self.idCategory = idCategory
        self.categoryModel = categoryModel
        self.currencyCode = currencyCode
        self.goalId = goalId
    }
}
