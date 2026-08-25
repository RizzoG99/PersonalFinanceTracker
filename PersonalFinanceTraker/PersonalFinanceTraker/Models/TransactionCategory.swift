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

    init(systemImage: String, label: String) {
        self.id = UUID()
        self.systemImage = systemImage
        self.label = label
    }

    static let incomeCategories: [TransactionCategory] = [
        TransactionCategory(systemImage: "banknote", label: "Salary"),
        TransactionCategory(systemImage: "gift", label: "Gift"),
        TransactionCategory(systemImage: "chart.line.uptrend.xyaxis", label: "Investment"),
        TransactionCategory(systemImage: "briefcase", label: "Freelance"),
        TransactionCategory(systemImage: "house", label: "Rental Income"),
        TransactionCategory(systemImage: "star.circle", label: "Bonus"),
        TransactionCategory(systemImage: "trophy", label: "Prize"),
        TransactionCategory(systemImage: "arrow.uturn.backward", label: "Refund"),
        TransactionCategory(systemImage: "ellipsis.circle", label: "Other"),
    ]

    static let expenseCategories: [TransactionCategory] = [
        // Food & Dining
        TransactionCategory(systemImage: "cart", label: "Groceries"),
        TransactionCategory(systemImage: "fork.knife", label: "Restaurants"),
        TransactionCategory(systemImage: "cup.and.saucer", label: "Coffee & Drinks"),
        TransactionCategory(systemImage: "takeoutbag.and.cup.and.straw", label: "Takeout"),

        // Transportation
        TransactionCategory(systemImage: "fuelpump", label: "Gas"),
        TransactionCategory(systemImage: "wrench.and.screwdriver", label: "Car Maintenance"),
        TransactionCategory(systemImage: "bus", label: "Public Transport"),
        TransactionCategory(systemImage: "car", label: "Taxi & Rideshare"),

        // Bills & Utilities
        TransactionCategory(systemImage: "house.fill", label: "Rent/Mortgage"),
        TransactionCategory(systemImage: "bolt", label: "Utilities"),
        TransactionCategory(systemImage: "iphone", label: "Phone Bill"),
        TransactionCategory(systemImage: "globe", label: "Internet"),
        TransactionCategory(systemImage: "tv", label: "Streaming Services"),

        // Shopping
        TransactionCategory(systemImage: "tshirt", label: "Clothing"),
        TransactionCategory(systemImage: "bag", label: "Shopping"),
        TransactionCategory(systemImage: "gamecontroller", label: "Electronics"),
        TransactionCategory(systemImage: "book", label: "Books & Education"),

        // Health & Fitness
        TransactionCategory(systemImage: "cross.case", label: "Healthcare"),
        TransactionCategory(systemImage: "pills", label: "Pharmacy"),
        TransactionCategory(systemImage: "dumbbell", label: "Gym & Fitness"),
        TransactionCategory(systemImage: "comb", label: "Personal Care"),

        // Entertainment
        TransactionCategory(systemImage: "film", label: "Entertainment"),
        TransactionCategory(systemImage: "music.note", label: "Music"),
        TransactionCategory(systemImage: "target", label: "Hobbies"),
        TransactionCategory(systemImage: "airplane", label: "Travel"),

        // Other
        TransactionCategory(systemImage: "graduationcap", label: "Education"),
        TransactionCategory(systemImage: "pawprint", label: "Pets"),
        TransactionCategory(systemImage: "creditcard", label: "Banking Fees"),
        TransactionCategory(systemImage: "ellipsis.circle", label: "Other")
    ]
    
    static let defaultCategories: [TransactionCategory] = incomeCategories + expenseCategories
}
