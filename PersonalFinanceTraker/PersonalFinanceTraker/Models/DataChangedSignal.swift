//
//  DataChangedSignal.swift
//  PersonalFinanceTraker
//

import Foundation

/// Single app-wide "persisted data changed" signal.
/// Mutation sites call bump(); interested views observe revision and reload,
/// replacing per-sheet manual reload() wiring.
@Observable @MainActor
final class DataChangedSignal {
    private(set) var revision = 0

    func bump() { revision += 1 }
}
