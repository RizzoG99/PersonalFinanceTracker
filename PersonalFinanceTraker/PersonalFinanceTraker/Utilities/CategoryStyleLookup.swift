//
//  CategoryStyleLookup.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

/// Saved icon and color per category, keyed by name *and* type ("Other" exists as both an
/// income and an expense). Rows that only know a category's name (upcoming charges, trip
/// breakdown, habit streaks) ask this first, so they match the category's own colors; a name
/// with no saved category falls back to `CategoryInfo`'s keyword guess (#249).
struct CategoryStyleLookup {
    private let styles: [String: CategoryInfo]

    init(_ categories: [CategorySnapshot]) {
        styles = Dictionary(
            categories.map { (Self.key($0.name, $0.type), CategoryInfo(color: Color(categoryToken: $0.colorToken), symbol: $0.systemImage)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func info(for name: String, type: TransactionType) -> CategoryInfo {
        styles[Self.key(name, type.rawValue)] ?? CategoryInfo.info(for: name)
    }

    private static func key(_ name: String, _ type: String) -> String { "\(type)|\(name)" }
}

extension EnvironmentValues {
    @Entry var categoryStyles = CategoryStyleLookup([])
}

private struct CategoryStylesModifier: ViewModifier {
    @Query private var categories: [CategoryModel]

    func body(content: Content) -> some View {
        content.environment(\.categoryStyles, CategoryStyleLookup(categories.map(CategorySnapshot.init)))
    }
}

extension View {
    /// Publishes the saved category styles to every descendant (sheets included). Applied once, at the app shell.
    func categoryStyles() -> some View { modifier(CategoryStylesModifier()) }
}
