//
//  TransactionCategory.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import Foundation

struct TransactionCategory: Identifiable, Hashable, Codable {
    let id: UUID
    let systemImage: String
    let label: String
    let colorToken: String

    init(systemImage: String, label: String, colorToken: String) {
        self.id = UUID()
        self.systemImage = systemImage
        self.label = label
        self.colorToken = colorToken
    }

    // Explicit icon + color per default (#249). Icons are the filled variants from
    // `CategoryConstants.symbolNames`; colors are chosen so categories used together never
    // share one, even within a family (Food, Transport, Bills...). Only Salary is green, and
    // no expense is, because green is the `positive` color.
    static let incomeCategories: [TransactionCategory] = [
        TransactionCategory(systemImage: "banknote.fill", label: "Salary", colorToken: "categoryGreen"),
        TransactionCategory(systemImage: "gift.fill", label: "Gift", colorToken: "categoryPink"),
        TransactionCategory(systemImage: "chart.line.uptrend.xyaxis.circle.fill", label: "Investment", colorToken: "categoryBlue"),
        TransactionCategory(systemImage: "briefcase.fill", label: "Freelance", colorToken: "categoryOrange"),
        TransactionCategory(systemImage: "building.2.fill", label: "Rental Income", colorToken: "categoryBrown"),
        TransactionCategory(systemImage: "star.fill", label: "Bonus", colorToken: "categoryAmber"),
        TransactionCategory(systemImage: "sparkles", label: "Prize", colorToken: "categoryPurple"),
        TransactionCategory(systemImage: "eurosign.circle.fill", label: "Refund", colorToken: "categoryTeal"),
        TransactionCategory(systemImage: "ellipsis.circle.fill", label: "Other", colorToken: "categoryGray"),
    ]

    /// Each inner array is a family of categories used together; colors never repeat inside one.
    static let expenseFamilies: [[TransactionCategory]] = [
        // Food & Dining
        [
            TransactionCategory(systemImage: "cart.fill", label: "Groceries", colorToken: "categoryOrange"),
            TransactionCategory(systemImage: "fork.knife", label: "Restaurants", colorToken: "categoryRed"),
            TransactionCategory(systemImage: "cup.and.saucer.fill", label: "Coffee & Drinks", colorToken: "categoryBrown"),
            TransactionCategory(systemImage: "takeoutbag.and.cup.and.straw.fill", label: "Takeout", colorToken: "categoryPink"),
        ],
        // Transportation
        [
            TransactionCategory(systemImage: "fuelpump.fill", label: "Gas", colorToken: "categoryRed"),
            TransactionCategory(systemImage: "hammer.fill", label: "Car Maintenance", colorToken: "categoryTeal"),
            TransactionCategory(systemImage: "bus.fill", label: "Public Transport", colorToken: "categoryIndigo"),
            TransactionCategory(systemImage: "car.fill", label: "Taxi & Rideshare", colorToken: "categoryAmber"),
        ],
        // Bills & Utilities
        [
            TransactionCategory(systemImage: "house.fill", label: "Rent/Mortgage", colorToken: "categoryBrown"),
            TransactionCategory(systemImage: "bolt.fill", label: "Utilities", colorToken: "categoryTeal"),
            TransactionCategory(systemImage: "phone.fill", label: "Phone Bill", colorToken: "categoryBlue"),
            TransactionCategory(systemImage: "wifi.circle.fill", label: "Internet", colorToken: "categoryOrange"),
            TransactionCategory(systemImage: "film.fill", label: "Streaming Services", colorToken: "categoryPurple"),
        ],
        // Shopping
        [
            TransactionCategory(systemImage: "tshirt.fill", label: "Clothing", colorToken: "categoryPink"),
            TransactionCategory(systemImage: "bag.fill", label: "Shopping", colorToken: "categoryAmber"),
            TransactionCategory(systemImage: "laptopcomputer", label: "Electronics", colorToken: "categoryIndigo"),
            TransactionCategory(systemImage: "books.vertical.fill", label: "Books & Education", colorToken: "categoryBrown"),
        ],
        // Health & Fitness
        [
            TransactionCategory(systemImage: "cross.case.fill", label: "Healthcare", colorToken: "categoryRed"),
            TransactionCategory(systemImage: "pills.fill", label: "Pharmacy", colorToken: "categoryTeal"),
            TransactionCategory(systemImage: "dumbbell.fill", label: "Gym & Fitness", colorToken: "categoryOrange"),
            TransactionCategory(systemImage: "scissors.circle.fill", label: "Personal Care", colorToken: "categoryPink"),
        ],
        // Entertainment
        [
            TransactionCategory(systemImage: "gamecontroller.fill", label: "Entertainment", colorToken: "categoryIndigo"),
            TransactionCategory(systemImage: "music.note", label: "Music", colorToken: "categoryOrange"),
            TransactionCategory(systemImage: "paintbrush.fill", label: "Hobbies", colorToken: "categoryTeal"),
            TransactionCategory(systemImage: "airplane", label: "Travel", colorToken: "categoryRed"),
        ],
        // Other
        [
            TransactionCategory(systemImage: "graduationcap.fill", label: "Education", colorToken: "categoryBlue"),
            TransactionCategory(systemImage: "pawprint.fill", label: "Pets", colorToken: "categoryAmber"),
            TransactionCategory(systemImage: "creditcard.fill", label: "Banking Fees", colorToken: "categoryIndigo"),
            TransactionCategory(systemImage: "ellipsis.circle.fill", label: "Other", colorToken: "categoryGray"),
        ],
    ]

    static let expenseCategories: [TransactionCategory] = expenseFamilies.flatMap { $0 }

    static let defaultCategories: [TransactionCategory] = incomeCategories + expenseCategories
}
