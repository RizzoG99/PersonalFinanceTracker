//
//  DefaultCategoryRefresh.swift
//  PersonalFinanceTraker
//

import Foundation
import SwiftData

/// One-time move of already-installed default categories to the explicit icon/color table (#249).
///
/// A stored Indigo can't be told apart from an Indigo the user picked, so this only touches a
/// field that still holds the exact value the old seeding wrote for that name and type. Icon
/// and color are checked separately: someone who recolored "Gas" keeps their color but still
/// gets the filled icon. Anything else (renamed, other icon, other color) is left alone.
enum DefaultCategoryRefresh {
    static let flagKey = "defaultCategoriesRefreshedV249"

    /// What the pre-#249 seeding stored for each default (icon, color token).
    private static let legacyIncome: [String: (icon: String, color: String)] = [
        "Salary": ("banknote", "categoryGreen"),
        "Gift": ("gift", "categoryGreen"),
        "Investment": ("chart.line.uptrend.xyaxis", "categoryGreen"),
        "Freelance": ("briefcase", "categoryGreen"),
        "Rental Income": ("house", "categoryGreen"),
        "Bonus": ("star.circle", "categoryGreen"),
        "Prize": ("trophy", "categoryGreen"),
        "Refund": ("arrow.uturn.backward", "categoryGreen"),
        "Other": ("ellipsis.circle", "categoryGray"),
    ]

    private static let legacyExpense: [String: (icon: String, color: String)] = [
        "Groceries": ("cart", "categoryGreen"),
        "Restaurants": ("fork.knife", "categoryAmber"),
        "Coffee & Drinks": ("cup.and.saucer", "categoryAmber"),
        "Takeout": ("takeoutbag.and.cup.and.straw", "categoryAmber"),
        "Gas": ("fuelpump", "categoryIndigo"),
        "Car Maintenance": ("wrench.and.screwdriver", "categoryIndigo"),
        "Public Transport": ("bus", "categoryIndigo"),
        "Taxi & Rideshare": ("car", "categoryIndigo"),
        "Rent/Mortgage": ("house.fill", "categoryIndigo"),
        "Utilities": ("bolt", "categoryIndigo"),
        "Phone Bill": ("iphone", "categoryIndigo"),
        "Internet": ("globe", "categoryIndigo"),
        "Streaming Services": ("tv", "categoryPurple"),
        "Clothing": ("tshirt", "categoryPink"),
        "Shopping": ("bag", "categoryPink"),
        "Electronics": ("gamecontroller", "categoryPink"),
        "Books & Education": ("book", "categoryPurple"),
        "Healthcare": ("cross.case", "categoryTeal"),
        "Pharmacy": ("pills", "categoryTeal"),
        "Gym & Fitness": ("dumbbell", "categoryTeal"),
        "Personal Care": ("comb", "categoryTeal"),
        "Entertainment": ("film", "categoryAmber"),
        "Music": ("music.note", "categoryPurple"),
        "Hobbies": ("target", "categoryPurple"),
        "Travel": ("airplane", "categoryAmber"),
        "Education": ("graduationcap", "categoryTeal"),
        "Pets": ("pawprint", "categoryTeal"),
        "Banking Fees": ("creditcard", "categoryIndigo"),
        "Other": ("ellipsis.circle", "categoryGray"),
    ]

    /// Runs once per install; a fresh install (already on the new table) is a no-op.
    @MainActor
    static func runIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: flagKey) else { return }
        // Flag only after a successful fetch and save, so a failure retries on the next launch.
        guard let categories = try? context.fetch(FetchDescriptor<CategoryModel>()) else { return }
        apply(to: categories)
        guard (try? context.save()) != nil else { return }
        defaults.set(true, forKey: flagKey)
    }

    static func apply(to categories: [CategoryModel]) {
        for category in categories {
            let isIncome = category.transactionType == .income
            let legacy = (isIncome ? legacyIncome : legacyExpense)[category.name]
            let current = (isIncome ? TransactionCategory.incomeCategories : TransactionCategory.expenseCategories)
                .first { $0.label == category.name }
            guard let legacy, let current else { continue }
            if category.systemImage == legacy.icon { category.systemImage = current.systemImage }
            if category.colorToken == legacy.color { category.colorToken = current.colorToken }
        }
    }
}
