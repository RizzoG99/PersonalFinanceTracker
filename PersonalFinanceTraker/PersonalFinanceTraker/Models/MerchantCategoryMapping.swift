//
//  MerchantCategoryMapping.swift
//  PersonalFinanceTraker
//
//  Learned from scan-originated transactions only: each time a scanned receipt's transaction is
//  saved, the merchant/category pairing lands here so the next scan of the same merchant is
//  pre-filled correctly. See docs/features/2026-08-27-scan-receipt-autofill.md.
//

import SwiftData
import Foundation

@Model
final class MerchantCategoryMapping {
    /// Normalized (lowercased, trimmed) merchant string — the natural key. Unique so re-saving the
    /// same merchant upserts the learned category instead of accumulating duplicate rows.
    @Attribute(.unique) var merchant: String
    var categoryId: UUID

    init(merchant: String, categoryId: UUID) {
        self.merchant = merchant
        self.categoryId = categoryId
    }
}
