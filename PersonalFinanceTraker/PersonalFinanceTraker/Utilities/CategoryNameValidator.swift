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
}
