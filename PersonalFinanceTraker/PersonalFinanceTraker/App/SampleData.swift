//
//  SampleData.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import Foundation
import SwiftData

struct SampleData {
    static func createSampleTransactions() -> [TransactionModel] {
        let calendar = Calendar.current
        let now = Date()
        
        return [
            // Today's transactions
            TransactionModel(
                timestamp: calendar.date(byAdding: .hour, value: -1, to: now) ?? now,
                amount: Decimal(-4.50),
                note: "Morning coffee",
                category: "☕ Coffee & Drinks"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .hour, value: -3, to: now) ?? now,
                amount: Decimal(-12.99),
                note: "Lunch at bistro",
                category: "🍕 Restaurants"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .hour, value: -5, to: now) ?? now,
                amount: Decimal(2500.00),
                note: "Monthly salary",
                category: "💰 Salary"
            ),
            
            // Yesterday's transactions
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                amount: Decimal(-45.67),
                note: "Weekly groceries",
                category: "🛒 Groceries"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                amount: Decimal(-8.99),
                note: "Netflix subscription",
                category: "📺 Streaming Services"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                amount: Decimal(-25.00),
                note: "Gas station",
                category: "⛽ Gas"
            ),
            
            // 2 days ago
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
                amount: Decimal(-15.50),
                note: "Coffee shop meeting",
                category: "☕ Coffee & Drinks"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
                amount: Decimal(-89.99),
                note: "New running shoes",
                category: "👕 Clothing"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
                amount: Decimal(50.00),
                note: "Birthday gift money",
                category: "🎁 Gift"
            ),
            
            // 3 days ago
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
                amount: Decimal(-1200.00),
                note: "Monthly rent",
                category: "🏠 Rent/Mortgage"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
                amount: Decimal(-65.43),
                note: "Electricity bill",
                category: "⚡ Utilities"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
                amount: Decimal(-30.00),
                note: "Phone bill",
                category: "📱 Phone Bill"
            ),
            
            // Last week
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -7, to: now) ?? now,
                amount: Decimal(-120.00),
                note: "Doctor visit",
                category: "🏥 Healthcare"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -7, to: now) ?? now,
                amount: Decimal(200.00),
                note: "Freelance project",
                category: "💼 Freelance"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -8, to: now) ?? now,
                amount: Decimal(-67.89),
                note: "Dinner with friends",
                category: "🍕 Restaurants"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -9, to: now) ?? now,
                amount: Decimal(-39.99),
                note: "Gym membership",
                category: "🏋️ Gym & Fitness"
            ),
            
            // Older transactions
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -12, to: now) ?? now,
                amount: Decimal(-450.00),
                note: "Car insurance",
                category: "🚗 Car Maintenance"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -15, to: now) ?? now,
                amount: Decimal(150.00),
                note: "Sold old books",
                category: "💵 Other"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -18, to: now) ?? now,
                amount: Decimal(-28.50),
                note: "Movie tickets",
                category: "🎬 Entertainment"
            ),
            TransactionModel(
                timestamp: calendar.date(byAdding: .day, value: -20, to: now) ?? now,
                amount: Decimal(-95.00),
                note: "Vet visit for cat",
                category: "🐕 Pets"
            )
        ]
    }
    
    static func populateModelContext(_ modelContext: ModelContext) {
        let sampleTransactions = createSampleTransactions()
        
        for transaction in sampleTransactions {
            modelContext.insert(transaction)
        }
        
        try? modelContext.save()
    }
}
