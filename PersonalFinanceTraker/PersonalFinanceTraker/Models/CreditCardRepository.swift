//
//  CreditCardRepository.swift
//  PersonalFinanceTraker
//

import SwiftData
import Foundation

final class CreditCardRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() throws -> [CreditCardModel] {
        let desc = FetchDescriptor<CreditCardModel>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(desc)
    }

    func add(_ item: CreditCardModel) throws {
        context.insert(item)
        try context.save()
    }

    func delete(_ item: CreditCardModel) throws {
        context.delete(item)
        try context.save()
    }

    func update() throws {
        try context.save()
    }
}
