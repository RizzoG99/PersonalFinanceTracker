//
//  StringEmojiExtension.swift
//  PersonalFinanceTraker
//

import Foundation

extension String {
    /// Removes leading emoji, pictographic characters, and following whitespace from the string.
    /// If the entire string consists only of emoji/pictographic characters, returns the original string.
    ///
    /// Examples:
    /// - "☕ Coffee & Drinks" → "Coffee & Drinks"
    /// - "🛒 Spesa" → "Spesa"
    /// - "Coffee" → "Coffee"
    /// - "☕" → "☕" (fallback to original if only emoji)
    var removingLeadingEmoji: String {
        var result = self

        while !result.isEmpty {
            let first = result.first.map { String($0) } ?? ""

            // Check if the first character is emoji or pictographic
            if first.rangeOfCharacter(from: .symbols) != nil ||
               isEmojiCharacter(first) {
                result.removeFirst()
            } else if first.trimmingCharacters(in: .whitespaces).isEmpty {
                // Remove whitespace after emoji
                result.removeFirst()
            } else {
                // Stop if we hit a non-emoji, non-whitespace character
                break
            }
        }

        // If we removed everything, return the original string
        return result.isEmpty ? self : result
    }

    /// Checks if a string character is an emoji
    private func isEmojiCharacter(_ char: String) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }

        // Check various emoji ranges
        let emojiRanges: [ClosedRange<UInt32>] = [
            0x1F300...0x1F9FF, // Misc Symbols and Pictographs, Emoticons, Transport, etc.
            0x2600...0x27BF,   // Misc symbols and Dingbats
            0x1F600...0x1F64F, // Emoticons
            0x1F900...0x1F9FF, // Supplemental Symbols and Pictographs
            0x1FA00...0x1FA6F, // Chess Symbols
            0x1FA70...0x1FAFF, // Symbols and Pictographs Extended-A
        ]

        return emojiRanges.contains { $0.contains(scalar.value) }
    }

    /// Localizes a category name for display, without touching the stored value.
    /// Category strings (`TransactionModel.category`, `CategoryModel.name`) are used as
    /// match keys for icon/color lookup (`CategoryInfo`) and CSV import — translating them
    /// in place would break that matching. This only translates the ~36 built-in category
    /// names (seeded in `Localizable.xcstrings`); custom/unmatched names pass through verbatim.
    var localizedCategoryDisplay: String {
        String(localized: String.LocalizationValue(self))
    }
}
