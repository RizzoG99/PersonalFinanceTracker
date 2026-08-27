//
//  ReceiptCategoryInferrer.swift
//  PersonalFinanceTraker
//
//  Category is a required field, so a scan must always produce one — even a wrong one the user
//  corrects, since correction is exactly what teaches the learned tier. Three tiers, cheapest and
//  most-trusted first. See docs/features/2026-08-27-scan-receipt-autofill.md.
//

import Foundation
import SwiftData

enum ReceiptCategoryInferrer {

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
        ("motorrad", "moto"), ("moto", "moto"),
        ("palestra", "palestra"), ("hotel", "hotel"),
    ]

    /// - Parameters:
    ///   - merchant: the parser's cleaned merchant guess, if any.
    ///   - learnedMerchants: normalized-merchant → category, built once from `MerchantCategoryMapping` rows.
    ///   - usage: transaction count per category, already computed by the view model for the chip picker —
    ///     reused here as the last-resort "most used" fallback.
    static func infer(
        merchant: String?,
        transactionType: TransactionType,
        categories: [CategorySnapshot],
        learnedMerchants: [String: UUID],
        usage: [PersistentIdentifier: Int]
    ) -> CategorySnapshot? {
        let pool = CategoryAutoMapper.pool(for: transactionType, in: categories)
        guard !pool.isEmpty else { return nil }

        if let merchant, let categoryId = learnedMerchants[normalize(merchant)],
           let learned = pool.first(where: { $0.id == categoryId }) {
            return learned
        }

        if let merchant {
            let lower = merchant.lowercased()
            if let hit = merchantKeywords.first(where: { lower.contains($0.match) }),
               let matched = CategoryAutoMapper.bestMatch(for: hit.keyword, in: pool) {
                return matched
            }
        }

        // Last resort: most-used category for this type, so the required field is never empty.
        return pool.max { (usage[$0.persistentId] ?? 0) < (usage[$1.persistentId] ?? 0) }
    }

    /// Same normalization on write (saving a mapping) and read (looking one up), so casing/whitespace
    /// differences between two OCR passes of the same receipt don't create two learned entries.
    static func normalize(_ merchant: String) -> String {
        merchant.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
