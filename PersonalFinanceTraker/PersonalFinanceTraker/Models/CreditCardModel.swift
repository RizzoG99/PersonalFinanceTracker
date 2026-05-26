//
//  CreditCardModel.swift
//  PersonalFinanceTraker
//

import Foundation
import SwiftData

@Model
final class CreditCardModel {
    var id: UUID
    var name: String
    var lastFour: String
    var balance: Decimal
    var limit: Decimal
    var colorName: String = "accentIndigo"
    var currencyCode: String = "EUR"

    init(id: UUID = UUID(),
         name: String,
         lastFour: String,
         balance: Decimal,
         limit: Decimal,
         colorName: String = "accentIndigo",
         currencyCode: String = "EUR") {
        self.id = id
        self.name = name
        self.lastFour = lastFour
        self.balance = balance
        self.limit = limit
        self.colorName = colorName
        self.currencyCode = currencyCode
    }

    var utilizationRate: Double {
        guard limit > 0 else { return 0 }
        return min(1.0, Double(truncating: (balance / limit) as NSDecimalNumber))
    }

    var available: Decimal {
        max(0, limit - balance)
    }
}
