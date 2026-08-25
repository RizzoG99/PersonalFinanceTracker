//
//  CategoryNameValidator.swift
//  PersonalFinanceTraker
//

import Foundation

enum CategoryNameValidator {
    private static let allowedCharacters: CharacterSet = {
        var characters = CharacterSet.letters
        characters.formUnion(.decimalDigits)
        characters.formUnion(.whitespaces)
        characters.formUnion(CharacterSet(charactersIn: "&/-'.,()"))
        return characters
    }()

    static func isValid(_ name: String) -> Bool {
        name.unicodeScalars.allSatisfy(allowedCharacters.contains)
    }

    /// Names are unique **per type** — Expense and Income can each own an "Other".
    /// Callers pass the names already filtered to the relevant transaction type.
    static func isDuplicate(_ name: String, among names: some Sequence<String>) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespaces).lowercased()
        return names.contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == normalized }
    }
}
