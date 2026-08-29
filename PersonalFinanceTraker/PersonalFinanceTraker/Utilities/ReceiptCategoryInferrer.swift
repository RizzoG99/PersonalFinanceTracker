//
//  ReceiptCategoryInferrer.swift
//  PersonalFinanceTraker
//
//  Category is a required field, so a scan must always produce one — even a wrong one the user
//  corrects, since correction is exactly what teaches the learned tier. Four tiers, cheapest and
//  most-trusted first — the MapKit lookup only runs when the first two find nothing, so a scan
//  with an obvious merchant (a supermarket chain, say) never pays for a network round trip.
//  See docs/features/2026-08-27-scan-receipt-autofill.md.
//

import Foundation
import SwiftData

enum ReceiptCategoryInferrer {

    /// A category, plus whether it was actually derived from *this* receipt.
    ///
    /// The distinction matters because category is a required field, so the last tier returns the
    /// user's most-used category no matter what — a value carrying no information about the receipt
    /// at all. Reported as a plain result it is indistinguishable from a real read, which is how a
    /// €5 gelato came back as "Banking Fees" looking every bit as settled as the amount beside it.
    /// The caller needs to be able to say "I guessed" rather than "I filled this in".
    struct Inference: Sendable {
        let category: CategorySnapshot
        /// True when no tier recognized the merchant and this is only the most-used fallback.
        let isGuess: Bool
    }

    /// Merchant substring → canonical keyword already known to `CategoryAutoMapper`. Small and
    /// Italian-specific on purpose: a merchant directory is out of scope, this only needs to bridge
    /// a brand name to the generic concept `CategoryAutoMapper` already matches against the user's
    /// real categories.
    private static let merchantKeywords: [(match: String, keyword: String)] = [
        ("farmacia", "farmacia"),
        ("conad", "spesa"), ("esselunga", "spesa"), ("coop", "spesa"), ("lidl", "spesa"),
        ("carrefour", "spesa"), ("eurospin", "spesa"), ("pam ", "spesa"), ("despar", "spesa"),
        ("eni", "benzina"), ("q8", "benzina"), ("esso", "benzina"), ("tamoil", "benzina"), ("ip ", "benzina"),
        ("ristorante", "ristorante"), ("pizzeria", "ristorante"), ("trattoria", "ristorante"),
        ("bar ", "bar"), ("caffè", "bar"), ("caffe", "bar"),
        // A gelateria is the shape of merchant this tier exists for: a real category is obvious to
        // a person and invisible to the matcher, because the shop's name shares no word with any
        // category. Without these, "Cremeria" fell through every tier to the most-used fallback and
        // came back as "Banking Fees" (device log, 2026-08-29) — a required field filled with
        // something actively wrong rather than merely generic.
        ("gelateria", "bar"), ("gelato", "bar"), ("cremeria", "bar"), ("pasticceria", "bar"),
        ("motorrad", "moto"), ("moto", "moto"),
        ("palestra", "palestra"), ("hotel", "hotel"),
    ]

    /// - Parameters:
    ///   - merchant: the parser's cleaned merchant guess, if any.
    ///   - merchantAddress: the receipt's own printed street/city line, if present — passed through
    ///     to `MerchantCategoryLookup` to narrow its MapKit search; never the device's location.
    ///   - learnedMerchants: normalized-merchant → category, built once from `MerchantCategoryMapping` rows.
    ///   - usage: transaction count per category, already computed by the view model for the chip picker —
    ///     reused here as the last-resort "most used" fallback.
    static func infer(
        merchant: String?,
        merchantAddress: String?,
        transactionType: TransactionType,
        categories: [CategorySnapshot],
        learnedMerchants: [String: UUID],
        usage: [PersistentIdentifier: Int]
    ) async -> Inference? {
        let pool = CategoryAutoMapper.pool(for: transactionType, in: categories)
        guard !pool.isEmpty else { return nil }

        if let merchant, let categoryId = learnedMerchants[normalize(merchant)],
           let learned = pool.first(where: { $0.id == categoryId }) {
            return Inference(category: learned, isGuess: false)
        }

        if let merchant {
            // Padded so a trailing-space keyword like "bar " still matches a merchant that
            // *ends* with it, e.g. "Camilla-Nu Bar" — contains() alone never sees that space.
            let lower = " " + merchant.lowercased() + " "
            if let hit = merchantKeywords.first(where: { lower.contains($0.match) }),
               let matched = resolve(hit.keyword, in: pool) {
                return Inference(category: matched, isGuess: false)
            }
        }

        // A network round trip, only reached when the merchant's name alone gave nothing to go
        // on (e.g. "Barrueco S.R.L." — a real restaurant with no generic word in its name).
        if let merchant,
           let hint = await MerchantCategoryLookup.lookupKeyword(merchant: merchant, address: merchantAddress),
           let matched = resolve(hint, in: pool) {
            return Inference(category: matched, isGuess: false)
        }

        // Last resort: most-used category for this type, so the required field is never empty.
        // Flagged as a guess — it is the user's habit, not anything this receipt said.
        return pool
            .max { (usage[$0.persistentId] ?? 0) < (usage[$1.persistentId] ?? 0) }
            .map { Inference(category: $0, isGuess: true) }
    }

    /// Turns a keyword into one of the user's categories, asking the user's own concept → category
    /// pairing from Settings first and only then falling back to matching the keyword against
    /// category *names*. Name matching can only work for a category named in one of the languages
    /// `CategoryAutoMapper` knows; the explicit pairing works for any name the user invents.
    private static func resolve(_ keyword: String, in pool: [CategorySnapshot]) -> CategorySnapshot? {
        ReceiptCategoryMap.category(forKeyword: keyword, in: pool)
            ?? CategoryAutoMapper.bestMatch(for: keyword, in: pool)
    }

    /// Same normalization on write (saving a mapping) and read (looking one up), so casing/whitespace
    /// differences between two OCR passes of the same receipt don't create two learned entries.
    static func normalize(_ merchant: String) -> String {
        merchant.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
