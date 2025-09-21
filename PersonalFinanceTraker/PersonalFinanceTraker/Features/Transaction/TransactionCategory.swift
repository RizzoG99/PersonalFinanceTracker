//
//  TransactionCategory.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import Foundation

struct TransactionCategory: Identifiable, Hashable, Codable {
    let id: UUID
    let emoji: String
    let label: String
    
    init(emoji: String, label: String) {
        self.id = UUID()
        self.emoji = emoji
        self.label = label
    }
    
    static let incomeCategories: [TransactionCategory] = [
        TransactionCategory(emoji: "💰", label: "Salary"),
        TransactionCategory(emoji: "🎁", label: "Gift"),
        TransactionCategory(emoji: "📈", label: "Investment"),
        TransactionCategory(emoji: "💼", label: "Freelance"),
        TransactionCategory(emoji: "🏠", label: "Rental Income"),
        TransactionCategory(emoji: "💵", label: "Bonus"),
        TransactionCategory(emoji: "🏆", label: "Prize"),
        TransactionCategory(emoji: "💳", label: "Refund"),
    ]
    
    static let expenseCategories: [TransactionCategory] = [
        // Food & Dining
        TransactionCategory(emoji: "🛒", label: "Groceries"),
        TransactionCategory(emoji: "🍕", label: "Restaurants"),
        TransactionCategory(emoji: "☕", label: "Coffee & Drinks"),
        TransactionCategory(emoji: "🥡", label: "Takeout"),
        
        // Transportation
        TransactionCategory(emoji: "⛽", label: "Gas"),
        TransactionCategory(emoji: "🚗", label: "Car Maintenance"),
        TransactionCategory(emoji: "🚌", label: "Public Transport"),
        TransactionCategory(emoji: "🚕", label: "Taxi & Rideshare"),
        
        // Bills & Utilities
        TransactionCategory(emoji: "🏠", label: "Rent/Mortgage"),
        TransactionCategory(emoji: "⚡", label: "Utilities"),
        TransactionCategory(emoji: "📱", label: "Phone Bill"),
        TransactionCategory(emoji: "🌐", label: "Internet"),
        TransactionCategory(emoji: "📺", label: "Streaming Services"),
        
        // Shopping
        TransactionCategory(emoji: "👕", label: "Clothing"),
        TransactionCategory(emoji: "🛍️", label: "Shopping"),
        TransactionCategory(emoji: "🎮", label: "Electronics"),
        TransactionCategory(emoji: "📚", label: "Books & Education"),
        
        // Health & Fitness
        TransactionCategory(emoji: "🏥", label: "Healthcare"),
        TransactionCategory(emoji: "💊", label: "Pharmacy"),
        TransactionCategory(emoji: "🏋️", label: "Gym & Fitness"),
        TransactionCategory(emoji: "💄", label: "Personal Care"),
        
        // Entertainment
        TransactionCategory(emoji: "🎬", label: "Entertainment"),
        TransactionCategory(emoji: "🎵", label: "Music"),
        TransactionCategory(emoji: "🎯", label: "Hobbies"),
        TransactionCategory(emoji: "✈️", label: "Travel"),
        
        // Other
        TransactionCategory(emoji: "🎓", label: "Education"),
        TransactionCategory(emoji: "🐕", label: "Pets"),
        TransactionCategory(emoji: "💳", label: "Banking Fees"),
        TransactionCategory(emoji: "❓", label: "Other")
    ]
    
    static let defaultCategories: [TransactionCategory] = incomeCategories + expenseCategories
    
    var displayText: String {
        "\(emoji) \(label)"
    }
}
