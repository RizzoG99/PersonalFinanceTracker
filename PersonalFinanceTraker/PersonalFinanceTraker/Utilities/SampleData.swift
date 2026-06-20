//
//  SampleData.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import Foundation
import SwiftData
import SwiftUI

struct SampleData {
    static func createSampleCategories() -> [CategoryModel] {
        var categories: [CategoryModel] = []
        
        for cat in TransactionCategory.incomeCategories {
            categories.append(CategoryModel(
                name: cat.label,
                systemImage: cat.systemImage,
                type: .income,
                colorToken: CategoryConstants.colorToken(forName: cat.label),
                currencyCode: "EUR"
            ))
        }

        for cat in TransactionCategory.expenseCategories {
            categories.append(CategoryModel(
                name: cat.label,
                systemImage: cat.systemImage,
                type: .expense,
                colorToken: CategoryConstants.colorToken(forName: cat.label),
                currencyCode: "EUR"
            ))
        }
        
        return categories
    }
    
    static func createSampleTransactions(categories: [CategoryModel]) -> [TransactionModel] {
        let calendar = Calendar.current
        let now = Date()
        
        func findCategory(named: String) -> CategoryModel? {
            return categories.first(where: { named.contains($0.name) })
        }
        
        let coffeeCat = findCategory(named: "Coffee & Drinks")
        let restaurantCat = findCategory(named: "Restaurants")
        let salaryCat = findCategory(named: "Salary")
        let groceryCat = findCategory(named: "Groceries")
        let streamingCat = findCategory(named: "Streaming Services")
        let gasCat = findCategory(named: "Gas")
        let clothingCat = findCategory(named: "Clothing")
        let giftCat = findCategory(named: "Gift")
        let rentCat = findCategory(named: "Rent/Mortgage")
        let utilityCat = findCategory(named: "Utilities")
        let phoneCat = findCategory(named: "Phone Bill")
        let healthcareCat = findCategory(named: "Healthcare")
        let freelanceCat = findCategory(named: "Freelance")
        let gymCat = findCategory(named: "Gym & Fitness")
        let carCat = findCategory(named: "Car Maintenance")
        let otherCat = findCategory(named: "Other")
        let entertainmentCat = findCategory(named: "Entertainment")
        let petCat = findCategory(named: "Pets")

        return [
            // Today's transactions
            TransactionModel(
                timestamp: calendar.date(byAdding: .hour, value: -1, to: now) ?? now,
                amount: Decimal(-4.50),
                note: "Morning coffee",
                category: coffeeCat?.name ?? "",
                categoryModel: coffeeCat,
                currencyCode: "EUR"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .hour, value: -3, to: now) ?? now,
                amount: Decimal(-12.99),
                note: "Lunch at bistro",
                category: restaurantCat?.name ?? "",
                categoryModel: restaurantCat
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .hour, value: -5, to: now) ?? now,
                amount: Decimal(2500.00),
                note: "Monthly salary",
                category: salaryCat?.name ?? "",
                categoryModel: salaryCat
            ),
            
            // Yesterday's transactions
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                amount: Decimal(-45.67),
                note: "Weekly groceries",
                category: groceryCat?.name ?? "",
                categoryModel: groceryCat
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                amount: Decimal(-8.99),
                note: "Netflix subscription",
                category: streamingCat?.name ?? "",
                categoryModel: streamingCat
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                amount: Decimal(-25.00),
                note: "Gas station",
                category: gasCat?.name ?? "",
                categoryModel: gasCat
            ),
            
            // 2 days ago
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
                amount: Decimal(-15.50),
                note: "Coffee shop meeting",
                category: coffeeCat?.name ?? "",
                categoryModel: coffeeCat
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
                amount: Decimal(-89.99),
                note: "New running shoes",
                category: clothingCat?.name ?? "",
                categoryModel: clothingCat
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
                amount: Decimal(50.00),
                note: "Birthday gift money",
                category: giftCat?.name ?? "",
                categoryModel: giftCat
            ),
            
            // 3 days ago
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
                amount: Decimal(-1200.00),
                note: "Monthly rent",
                category: rentCat?.name ?? "",
                categoryModel: rentCat
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
                amount: Decimal(-65.43),
                note: "Electricity bill",
                category: utilityCat?.name ?? "",
                categoryModel: utilityCat
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
                amount: Decimal(-30.00),
                note: "Phone bill",
                category: phoneCat?.name ?? "",
                categoryModel: phoneCat
            ),
            
            // Last week
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -7, to: now) ?? now,
                amount: Decimal(-120.00),
                note: "Doctor visit",
                category: healthcareCat?.name ?? "",
                categoryModel: healthcareCat
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -7, to: now) ?? now,
                amount: Decimal(200.00),
                note: "Freelance project",
                category: freelanceCat?.name ?? "",
                categoryModel: freelanceCat
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -8, to: now) ?? now,
                amount: Decimal(-67.89),
                note: "Dinner with friends",
                category: restaurantCat?.name ?? "",
                categoryModel: restaurantCat
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -9, to: now) ?? now,
                amount: Decimal(-39.99),
                note: "Gym membership",
                category: gymCat?.name ?? "",
                categoryModel: gymCat
            ),
            
            // Older transactions
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -12, to: now) ?? now,
                amount: Decimal(-450.00),
                note: "Car insurance",
                category: carCat?.name ?? "",
                categoryModel: carCat
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -15, to: now) ?? now,
                amount: Decimal(150.00),
                note: "Sold old books",
                category: otherCat?.name ?? "",
                categoryModel: otherCat
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -18, to: now) ?? now,
                amount: Decimal(-28.50),
                note: "Movie tickets",
                category: entertainmentCat?.name ?? "",
                categoryModel: entertainmentCat
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -20, to: now) ?? now,
                amount: Decimal(-95.00),
                note: "Vet visit for cat",
                category: petCat?.name ?? "",
                categoryModel: petCat
            )
        ]
    }
    
    static func populateModelContext(_ modelContext: ModelContext) {
        // Only populate if empty
        let catDesc = FetchDescriptor<CategoryModel>()
        let count = (try? modelContext.fetchCount(catDesc)) ?? 0
        
        if count == 0 {
            let sampleCategories = createSampleCategories()
            for category in sampleCategories {
                modelContext.insert(category)
            }
            
            let sampleTransactions = createSampleTransactions(categories: sampleCategories)
            for transaction in sampleTransactions {
                modelContext.insert(transaction)
            }
            
            try? modelContext.save()
        }
    }
}
