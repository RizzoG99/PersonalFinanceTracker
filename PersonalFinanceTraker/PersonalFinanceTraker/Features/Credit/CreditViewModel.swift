//
//  CreditViewModel.swift
//  PersonalFinanceTraker
//

import Foundation

@Observable @MainActor
final class CreditViewModel {
    var creditCards: [CreditCardModel] = []
    var errorMessage: String? = nil

    private let repo: CreditCardRepository

    init(repo: CreditCardRepository) {
        self.repo = repo
    }

    func load() {
        do {
            creditCards = try repo.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addCard(_ card: CreditCardModel) {
        do {
            try repo.add(card)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCard(_ card: CreditCardModel) {
        do {
            try repo.delete(card)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveCardEdits() {
        do {
            try repo.update()
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var totalBalance: Decimal {
        creditCards.reduce(0) { $0 + $1.balance }
    }

    var totalLimit: Decimal {
        creditCards.reduce(0) { $0 + $1.limit }
    }

    var totalAvailable: Decimal {
        max(0, totalLimit - totalBalance)
    }

    var totalUtilization: Double {
        guard totalLimit > 0 else { return 0 }
        return min(1.0, Double(truncating: (totalBalance / totalLimit) as NSDecimalNumber))
    }
}
