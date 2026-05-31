//
//  TransactionListViewRepository.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 14/10/25.
//

import SwiftData
import Foundation

protocol ITransactionRepository {
    func fetchAll() throws -> [TransactionModel]
    func add(_ item: TransactionModel) throws
    func delete(_ item: TransactionModel) throws
    func update() throws

    // Category management
    func fetchCategories() throws -> [CategoryModel]
    func addCategory(_ item: CategoryModel) throws
    func deleteCategory(_ item: CategoryModel) throws

    // Goal management
    func fetchGoals() throws -> [GoalModel]
    func addGoal(_ item: GoalModel) throws
    func updateGoal() throws
    func deleteGoal(_ item: GoalModel) throws
}

final class TransactionRepository: ITransactionRepository {
    private let context: ModelContext
    
    init(context: ModelContext) {
        self.context = context
    }
    
    func fetchAll() throws -> [TransactionModel] {
        let desc = FetchDescriptor<TransactionModel>(sortBy: [SortDescriptor(\.timestamp)])
        return try context.fetch(desc)
    }
    
    func add(_ item: TransactionModel) throws {
        context.insert(item)
        try context.save()
    }
    
    func delete(_ item: TransactionModel) throws {
        context.delete(item)
        try context.save()
    }
    
    func update() throws {
        try context.save()
    }
    
    func fetchCategories() throws -> [CategoryModel] {
        let desc = FetchDescriptor<CategoryModel>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(desc)
    }
    
    func addCategory(_ item: CategoryModel) throws {
        context.insert(item)
        try context.save()
    }
    
    func deleteCategory(_ item: CategoryModel) throws {
        context.delete(item)
        try context.save()
    }

    func fetchGoals() throws -> [GoalModel] {
        let desc = FetchDescriptor<GoalModel>(sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(desc)
    }

    func addGoal(_ item: GoalModel) throws {
        context.insert(item)
        try context.save()
    }

    func updateGoal() throws {
        try context.save()
    }

    func deleteGoal(_ item: GoalModel) throws {
        context.delete(item)
        try context.save()
    }
}
