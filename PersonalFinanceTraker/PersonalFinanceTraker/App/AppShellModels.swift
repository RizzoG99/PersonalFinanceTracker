//
//  AppShellModels.swift
//  PersonalFinanceTraker
//

import Foundation
import SwiftData

/// The repo, services and view models shared by both shells — `MainTabView` on iPhone and
/// `IPadRootView` on iPad.
///
/// Built once by `AuthenticationWrapper` and handed to whichever shell runs, so the two can't
/// drift apart: anything a shell needs has to be added here, in one place. It also outlives the
/// shells themselves, which are torn down and rebuilt on every PIN/biometric lock cycle — same
/// reasoning as `AppSettings`, which is owned up there for exactly that reason.
@MainActor
final class AppShellModels {
    let repo: TransactionActor
    let materializationService = RecurrenceMaterializationService()
    let transactions: TransactionListViewModel
    let dashboard: DashboardViewModel
    let compass: CompassViewModel
    let profile = ProfileViewModel()
    let dataChanged = DataChangedSignal()

    init(modelContainer: ModelContainer) {
        let actor = TransactionActor(modelContainer: modelContainer)
        repo = actor
        transactions = TransactionListViewModel(repo: actor)
        dashboard = DashboardViewModel(repo: actor)
        compass = CompassViewModel(repo: actor)
    }
}
