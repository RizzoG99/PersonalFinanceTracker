//
//  CategoryModel.swift
//  PersonalFinanceTraker
//
//  Created by Gemini CLI on 26/02/26.
//

import Foundation
import SwiftData
import SwiftUI

@Model
public final class CategoryModel {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var systemImage: String
    public var type: String // "income" or "expense"
    public var colorToken: String = "categoryIndigo"
    public var monthlyBudget: Decimal? = nil
    public var currencyCode: String = "EUR"

    @Relationship(deleteRule: .nullify, inverse: \TransactionModel.categoryModel)
    public var transactions: [TransactionModel]? = []

    public init(id: UUID = UUID(),
                name: String,
                systemImage: String,
                type: TransactionType,
                colorToken: String = "categoryIndigo",
                monthlyBudget: Decimal? = nil,
                currencyCode: String = "EUR") {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.type = type.rawValue
        self.colorToken = colorToken
        self.monthlyBudget = monthlyBudget
        self.currencyCode = currencyCode
    }

    public var transactionType: TransactionType {
        TransactionType(rawValue: type) ?? .expense
    }

    public var categoryColor: Color {
        CategoryConstants.color(forToken: colorToken)
    }

    public var displayText: String {
        name
    }
}
