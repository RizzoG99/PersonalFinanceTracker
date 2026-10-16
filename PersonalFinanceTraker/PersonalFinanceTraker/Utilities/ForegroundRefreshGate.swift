//
//  ForegroundRefreshGate.swift
//  PersonalFinanceTraker
//

/// Distinguishes the initial active phase, which bootstrap already covers, from a
/// later activation that may follow outside writes: a real return from background, or
/// an `.inactive` blip during which an in-process App Intent saved (the revision moved).
/// A blip with no write (Face ID, Control Center) skips the refresh.
struct ForegroundRefreshGate: Sendable {
    private var refreshPending = false
    private var lastRevision: UInt64?

    mutating func recordBackground() {
        refreshPending = true
    }

    mutating func consumeRefreshOnActivation(revision: UInt64) -> Bool {
        defer {
            refreshPending = false
            lastRevision = revision
        }
        guard let lastRevision else { return false }
        return refreshPending || revision != lastRevision
    }
}
