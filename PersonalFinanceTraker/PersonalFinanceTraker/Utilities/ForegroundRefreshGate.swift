//
//  ForegroundRefreshGate.swift
//  PersonalFinanceTraker
//

/// Distinguishes the initial active phase, which bootstrap already covers, from a
/// later return after the app actually entered the background.
struct ForegroundRefreshGate: Sendable {
    private var refreshPending = false

    mutating func recordBackground() {
        refreshPending = true
    }

    mutating func consumeRefreshOnActivation() -> Bool {
        defer { refreshPending = false }
        return refreshPending
    }
}
