//
//  MockTransactionRepository.swift
//  PersonalFinanceTrakerTests
//
//  import Foundation
@testable import PersonalFinanceTraker

final class MockTransactionRepository: ITransactionRepository {
    var transactions: [TransactionModel] = []
    var shouldFail: Bool = false
    
    // Track calls for verification (Spy pattern)
    var fetchAllCalled = false
    var addCalledCount = 0
    var deleteCalledCount = 0
    var updateCalledCount = 0

    func fetchAll() throws -> [TransactionModel] {
        fetchAllCalled = true
        if shouldFail { throw NSError(domain: "MockError", code: 1, userInfo: nil) }
        return transactions
    }

    func add(_ item: TransactionModel) throws {
        addCalledCount += 1
        if shouldFail { throw NSError(domain: "MockError", code: 2, userInfo: nil) }
        transactions.append(item)
    }

    func delete(_ item: TransactionModel) throws {
        deleteCalledCount += 1
        if let index = transactions.firstIndex(where: { $0.id == item.id }) {
            transactions.remove(at: index)
        }
        if shouldFail { throw NSError(domain: "MockError", code: 3, userInfo: nil) }
    }

    func update() throws {
        updateCalledCount += 1
        if shouldFail { throw NSError(domain: "MockError", code: 4, userInfo: nil) }
    }
}
