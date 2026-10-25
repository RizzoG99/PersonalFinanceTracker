//
//  CategoryConstants.swift
//  PersonalFinanceTraker
//

import SwiftUI

enum CategoryConstants {
    /// A themed run of icons in the picker. `titleKey` is a manual `CategoryCatalog.xcstrings` key.
    struct SymbolGroup: Identifiable {
        let titleKey: String
        let symbols: [String]

        var id: String { titleKey }
        var title: String { CategoryConstants.localized(titleKey) }
    }

    static let symbolGroups: [SymbolGroup] = [
        SymbolGroup(titleKey: "iconGroup.food", symbols: [
            "cart.fill", "fork.knife", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill",
            "birthday.cake.fill", "wineglass.fill"
        ]),
        SymbolGroup(titleKey: "iconGroup.transport", symbols: [
            "car.fill", "fuelpump.fill", "bus.fill", "tram.fill", "bicycle.circle.fill", "airplane",
            "motorcycle.fill", "moped.fill", "parkingsign.circle.fill", "signpost.right.fill"
        ]),
        SymbolGroup(titleKey: "iconGroup.home", symbols: [
            "house.fill", "bolt.fill", "drop.fill", "flame.fill", "wifi.circle.fill", "phone.fill",
            "hammer.fill", "washer.fill", "building.2.fill"
        ]),
        SymbolGroup(titleKey: "iconGroup.shopping", symbols: [
            "bag.fill", "tshirt.fill", "tag.fill", "shippingbox.fill", "basket.fill"
        ]),
        SymbolGroup(titleKey: "iconGroup.health", symbols: [
            "cross.case.fill", "heart.fill", "figure.run", "dumbbell.fill", "pills.fill",
            "heart.text.square.fill", "sportscourt.fill"
        ]),
        SymbolGroup(titleKey: "iconGroup.family", symbols: [
            "stroller.fill", "figure.2.and.child.holdinghands", "teddybear.fill"
        ]),
        SymbolGroup(titleKey: "iconGroup.lifestyle", symbols: [
            "person.fill", "scissors.circle.fill", "sparkles", "pawprint.fill", "hands.and.sparkles.fill",
            "gift.fill", "star.fill", "ellipsis.circle.fill"
        ]),
        SymbolGroup(titleKey: "iconGroup.entertainment", symbols: [
            "film.fill", "music.note", "gamecontroller.fill", "books.vertical.fill", "paintbrush.fill"
        ]),
        SymbolGroup(titleKey: "iconGroup.finance", symbols: [
            "banknote.fill", "chart.line.uptrend.xyaxis.circle.fill", "creditcard.fill", "building.columns.fill",
            "eurosign.circle.fill", "percent", "doc.text.fill", "umbrella.fill"
        ]),
        SymbolGroup(titleKey: "iconGroup.work", symbols: [
            "laptopcomputer", "briefcase.fill", "graduationcap.fill", "pencil.circle.fill"
        ]),
        SymbolGroup(titleKey: "iconGroup.travel", symbols: [
            "suitcase.fill", "leaf.fill", "sun.max.fill"
        ])
    ]

    static let symbolNames: [String] = symbolGroups.flatMap(\.symbols)
    private static let symbolNameSet = Set(symbolNames)

    // Ordered by hue so look-alikes (Orange/Amber/Brown, Blue/Indigo) sit side by side in the
    // picker and can be compared while choosing.
    static let colorTokenNames: [String] = [
        "categoryRed", "categoryOrange", "categoryAmber", "categoryBrown",
        "categoryGreen", "categoryTeal", "categoryBlue", "categoryIndigo",
        "categoryPurple", "categoryPink", "categoryGray"
    ]

    // One suggested color per icon group, applied when the user taps an icon in Add / CSV import
    // (not Edit). Never green: that is the `positive` color and would make an expense read as
    // income. Travel shares Red with Health; 11 groups, 10 usable colors.
    private static let groupColorTokens: [String: String] = [
        "iconGroup.food": "categoryOrange", "iconGroup.transport": "categoryIndigo",
        "iconGroup.home": "categoryBrown", "iconGroup.shopping": "categoryPink",
        "iconGroup.health": "categoryRed", "iconGroup.family": "categoryAmber",
        "iconGroup.lifestyle": "categoryGray", "iconGroup.entertainment": "categoryPurple",
        "iconGroup.finance": "categoryBlue", "iconGroup.work": "categoryTeal",
        "iconGroup.travel": "categoryRed"
    ]

    /// Color suggested for `symbol`, or nil when it is outside the catalog.
    static func suggestedColorToken(forSymbol symbol: String) -> String? {
        symbolGroups.first { $0.symbols.contains(symbol) }.flatMap { groupColorTokens[$0.titleKey] }
    }

    /// Spoken name for an icon. Saved categories can hold an older, unfilled variant of a
    /// catalog icon (`cart` for `cart.fill`, `bicycle` for `bicycle.circle.fill`), so try those
    /// before the generic fallback.
    static func symbolLabel(_ symbol: String) -> String {
        for candidate in [symbol, symbol + ".fill", symbol + ".circle.fill"] where symbolNameSet.contains(candidate) {
            return localized(candidate)
        }
        return String(localized: "Current icon")
    }

    static func colorLabel(_ token: String) -> String { localized(token) }

    /// Picker names live in their own `CategoryCatalog.xcstrings`, keyed on the symbol id /
    /// token name. Kept out of `Localizable` on purpose: `localizedCategoryDisplay` translates
    /// any key found there, so a user category named "wifi" or "percent" would otherwise be
    /// shown as "Internet". A new language adds one column to each catalog, nothing else.
    static let catalogTable = "CategoryCatalog"

    fileprivate static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), table: catalogTable)
    }

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
