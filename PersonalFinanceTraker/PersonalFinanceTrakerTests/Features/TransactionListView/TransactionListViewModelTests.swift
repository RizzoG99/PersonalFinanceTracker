//
//  TransactionListViewModelTests.swift
//  PersonalFinanceTrakerTests
//

import Testing
import Foundation
@testable import PersonalFinanceTraker

struct TransactionListViewModelTests {

    @Test @MainActor func testClearSearch() async throws {
        // 1. Arrange
        let mockRepo = MockTransactionRepository()
        let viewModel = TransactionListViewModel(repo: mockRepo)
        viewModel.searchText = "Coffee"

        // 2. Act
        // This should fail to compile or run until implemented
        viewModel.clearSearch()

        // 3. Assert
        #expect(viewModel.searchText == "")
    }

}
