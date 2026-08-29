//
//  PendingTransactionIntent.swift
//  PersonalFinanceTraker
//

import Observation

/// One-shot flags set by notification or Widget deep-link handlers and consumed by
/// MainTabView. The singleton lets app-level handlers coordinate with the tab view.
@Observable
final class PendingTransactionIntent {
    static let shared = PendingTransactionIntent()

    var shouldPresentAdd = false
    var shouldReviewHabitTemplate = false
    /// Set by the "Scan Receipt" widget deep link; MainTabView opens the camera directly.
    var shouldScanReceipt = false

    /// Returns true (and clears the flag) when the Add sheet should present now.
    /// When an edit sheet is already open the flag is left set — SwiftUI presents one
    /// sheet per anchor, so we defer rather than clear-with-no-present.
    func consume(isEditSheetOpen: Bool) -> Bool {
        guard shouldPresentAdd, !isEditSheetOpen else { return false }
        shouldPresentAdd = false
        return true
    }

    func consumeHabitTemplate(isSheetOpen: Bool) -> Bool {
        guard shouldReviewHabitTemplate, !isSheetOpen else { return false }
        shouldReviewHabitTemplate = false
        return true
    }
}
