//  AmountParser.swift
//  PersonalFinanceTraker

import Foundation

/// Shared parse/format for user-entered Decimal amounts across the app's
/// money-input screens (Budgets, Amount filter, Goal funds, Credit card,
/// and goals). Not for `CurrencyAmountField`, which is Double-based.
enum AmountParser {
    /// Keeps an in-progress amount entry valid as it is typed. Both common
    /// decimal keys are accepted, but the result always uses the locale's key.
    static func sanitizedInput(
        _ text: String,
        locale: Locale = .current,
        maximumFractionDigits: Int = 2
    ) -> String {
        if isValidLocalizedGrouping(
            text,
            locale: locale,
            maximumFractionDigits: maximumFractionDigits
        ) {
            return text
        }

        let decimalSeparator = locale.decimalSeparator ?? "."
        var result = ""
        var hasDecimalSeparator = false
        var fractionDigitCount = 0

        for character in text {
            if character.wholeNumberValue != nil {
                guard !hasDecimalSeparator || fractionDigitCount < maximumFractionDigits else { continue }
                result.append(character)
                if hasDecimalSeparator { fractionDigitCount += 1 }
            } else if (character == "." || character == ","),
                      !hasDecimalSeparator,
                      maximumFractionDigits > 0 {
                result.append(contentsOf: decimalSeparator)
                hasDecimalSeparator = true
            }
        }

        return result
    }

    private static func isValidLocalizedGrouping(
        _ text: String,
        locale: Locale,
        maximumFractionDigits: Int
    ) -> Bool {
        let groupingSeparator = locale.groupingSeparator ?? ","
        let decimalSeparator = locale.decimalSeparator ?? "."
        guard text.contains(groupingSeparator) else { return false }

        let decimalParts = text.components(separatedBy: decimalSeparator)
        guard decimalParts.count <= 2,
              let integerPart = decimalParts.first,
              !integerPart.isEmpty
        else { return false }

        if decimalParts.count == 2 {
            let fractionPart = decimalParts[1]
            guard maximumFractionDigits > 0,
                  (1...maximumFractionDigits).contains(fractionPart.count),
                  fractionPart.allSatisfy(\.isNumber)
            else { return false }
        }

        let groups = integerPart.components(separatedBy: groupingSeparator)
        guard groups.count > 1,
              (1...3).contains(groups[0].count),
              groups.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              groups.dropFirst().allSatisfy({ $0.count == 3 })
        else { return false }

        return true
    }

    /// Parses a localized number, also accepting `.` or `,` as an alternate
    /// decimal key when it is unambiguous. This supports external keyboards
    /// whose decimal key does not match the device locale.
    /// Returns nil for empty/unparseable input; when requirePositive, also
    /// nil for values <= 0.
    static func parse(
        _ text: String,
        requirePositive: Bool = false,
        locale: Locale = .current
    ) -> Decimal? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        formatter.generatesDecimalNumbers = true

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizedDecimalKey(in: trimmed, formatter: formatter)
        guard !normalized.isEmpty, let number = formatter.number(from: normalized) else { return nil }
        let value = number.decimalValue
        if requirePositive && value <= 0 { return nil }
        return value
    }

    private static func normalizedDecimalKey(in text: String, formatter: NumberFormatter) -> String {
        let localeDecimal = formatter.decimalSeparator ?? "."
        let alternateDecimal = localeDecimal == "." ? "," : "."

        // A single separator followed by one or two digits is an unambiguous
        // decimal entry. Three trailing digits remain a locale grouping entry
        // (for example, Italian `1.234`).
        guard !text.contains(localeDecimal),
              text.filter({ $0 == Character(alternateDecimal) }).count == 1,
              let separatorIndex = text.firstIndex(of: Character(alternateDecimal))
        else { return text }

        let fraction = text[text.index(after: separatorIndex)...]
        guard (1...2).contains(fraction.count), fraction.allSatisfy(\.isNumber) else { return text }

        return text.replacingOccurrences(of: alternateDecimal, with: localeDecimal)
    }

    /// Produces an ungrouped, locale-aware decimal string suitable for editing.
    /// This is intentionally separate from the currency display format: fields
    /// must round-trip persisted `Decimal` values without making `1.234` look
    /// like Italian thousands grouping when the user saves unchanged.
    static func editingText(_ value: Decimal, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 38

        let fallback = NSDecimalNumber(decimal: value).stringValue
            .replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? fallback
    }

    /// Currency display matching the convention already used by Budgets
    /// (`.formatted(.currency(code:))`).
    static func format(_ value: Decimal, currencyCode: String = "EUR") -> String {
        value.formatted(.currency(code: currencyCode))
    }
}
