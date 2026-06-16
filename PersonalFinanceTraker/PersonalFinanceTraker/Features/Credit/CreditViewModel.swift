//
//  CreditViewModel.swift
//  PersonalFinanceTraker
//

import Foundation

@Observable @MainActor
final class CreditViewModel {
    var creditCards: [CreditCardModel] = []
    var creditScore: Int
    var errorMessage: String? = nil

    private let repo: ICreditCardRepository
    private let scoreKey = "credit_score_value"

    init(repo: ICreditCardRepository) {
        self.repo = repo
        let stored = UserDefaults.standard.integer(forKey: scoreKey)
        creditScore = stored > 0 ? stored : 742
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

    func updateCreditScore(_ score: Int) {
        creditScore = score
        UserDefaults.standard.set(score, forKey: scoreKey)
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

    var creditStatusLabel: String {
        switch creditScore {
        case 800...: return "Excellent"
        case 740...: return "Very Good"
        case 670...: return "Good"
        case 580...: return "Fair"
        default: return "Poor"
        }
    }
}
