//
//  PendingTransactionIntent.swift
//  PersonalFinanceTraker
//

import Observation

/// One-shot flag set by the notification tap handler and consumed by MainTabView
/// to present the Add Transaction sheet. Singleton so the notification delegate can
/// reach it and so its value survives a cold launch (the instance is never torn down).
@Observable
final class PendingTransactionIntent {
    static let shared = PendingTransactionIntent()

    var shouldPresentAdd = false
    var shouldRepeatHabitTemplate = false

    /// Returns true (and clears the flag) when the Add sheet should present now.
    /// When an edit sheet is already open the flag is left set — SwiftUI presents one
    /// sheet per anchor, so we defer rather than clear-with-no-present.
    func consume(isEditSheetOpen: Bool) -> Bool {
        guard shouldPresentAdd, !isEditSheetOpen else { return false }
        shouldPresentAdd = false
        return true
    }

    func consumeHabitTemplate() -> Bool {
        guard shouldRepeatHabitTemplate else { return false }
        shouldRepeatHabitTemplate = false
        return true
    }
}
