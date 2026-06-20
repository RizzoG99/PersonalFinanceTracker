//
//  CategoryConstants.swift
//  PersonalFinanceTraker
//

import SwiftUI

enum CategoryConstants {
    static let symbolNames: [String] = [
        // Food & Dining
        "cart.fill", "fork.knife", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill",
        "birthday.cake.fill", "wineglass.fill",
        // Transportation
        "car.fill", "fuelpump.fill", "bus.fill", "tram.fill", "bicycle", "airplane",
        // Housing & Utilities
        "house.fill", "bolt.fill", "drop.fill", "flame.fill", "wifi", "phone.fill",
        // Shopping & Fashion
        "bag.fill", "tshirt.fill", "sparkles", "tag.fill",
        // Health & Fitness
        "cross.case.fill", "heart.fill", "figure.run", "dumbbell.fill", "pills.fill",
        // Entertainment & Leisure
        "film.fill", "music.note", "gamecontroller.fill", "books.vertical.fill", "paintbrush.fill",
        // Finance & Income
        "banknote.fill", "chart.line.uptrend.xyaxis", "creditcard.fill", "building.columns.fill",
        // Work & Education
        "laptopcomputer", "briefcase.fill", "graduationcap.fill", "pencil",
        // Travel & Nature
        "suitcase.fill", "pawprint.fill", "leaf.fill", "sun.max.fill",
        // Other
        "gift.fill", "star.fill", "person.fill", "ellipsis.circle.fill"
    ]

    static let colorTokenNames: [String] = [
        "categoryIndigo", "categoryGreen", "categoryAmber", "categoryPink",
        "categoryPurple", "categoryTeal", "categoryGray"
    ]

    // Maps a category name to its default color token, mirroring CategoryInfo keyword logic.
    // Used to pre-valorize the color picker for categories where the user hasn't set a color yet.
    static func colorToken(forName name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("grocer") || lower.contains("salary") || lower.contains("gift") ||
           lower.contains("invest") || lower.contains("freelance") || lower.contains("bonus") ||
           lower.contains("prize") || lower.contains("refund") || lower.contains("rental") {
            return "categoryGreen"
        } else if lower.contains("restaurant") || lower.contains("coffee") ||
                  lower.contains("takeout") || lower.contains("dining") || lower.contains("food") ||
                  lower.contains("entertainment") {
            return "categoryAmber"
        } else if lower.contains("gas") || lower.contains("car ") || lower == "car" || lower.contains("transport") ||
                  lower.contains("taxi") || lower.contains("rideshare") ||
                  lower.contains("rent") || lower.contains("mortgage") || lower.contains("utilities") ||
                  lower.contains("phone") || lower.contains("internet") || lower.contains("banking") {
            return "categoryIndigo"
        } else if lower.contains("shopping") || lower.contains("clothing") || lower.contains("electronics") {
            return "categoryPink"
        } else if lower.contains("streaming") || lower.contains("subscription") || lower.contains("music") ||
                  lower.contains("hobbies") || lower.contains("books") {
            return "categoryPurple"
        } else if lower.contains("health") || lower.contains("gym") || lower.contains("fitness") ||
                  lower.contains("pharmacy") || lower.contains("pet") || lower.contains("personal care") ||
                  lower.contains("education") {
            return "categoryTeal"
        } else if lower.contains("travel") {
            return "categoryAmber"
        } else {
            return "categoryGray"
        }
    }
}
