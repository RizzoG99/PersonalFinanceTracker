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
    /// Defers automatic maintenance (currently the daily backup) until the first shell load
    /// has made Home and Activity interactive.
    let bootstrapMaintenanceGate = BootstrapMaintenanceGate()
    /// Which tab the user was on, kept here (not as `@State` in `MainTabView`) so it survives
    /// the shell being torn down and rebuilt on every lock cycle — otherwise every relock would
    /// silently drop the user back onto Home.
    var selectedTab: TabItem = .home

    private var externalSnapshotRefreshPending = false
    private var foregroundSnapshotRefresh: Task<Void, Never>?

    func recordBackgroundForSnapshotRefresh() {
        externalSnapshotRefreshPending = true
    }

    /// Saves in this process advance the container revision automatically. A writer in
    /// another process cannot post didSave here, so every genuine background return clears
    /// the read model once, before either shell or maintenance is allowed to read it.
    func prepareForForegroundReads() async {
        if externalSnapshotRefreshPending {
            externalSnapshotRefreshPending = false
            let previous = foregroundSnapshotRefresh
            let repo = repo
            foregroundSnapshotRefresh = Task {
                await previous?.value
                await repo.invalidateTransactionSnapshotCache()
                PerformanceAuditRecorder.event("Lifecycle.foreground.snapshots.invalidated")
            }
        }
        // Concurrent shell/backup requests await the same invalidation instead of racing
        // past a flag cleared by the first caller before its actor hop has completed.
        await foregroundSnapshotRefresh?.value
    }

    init(modelContainer: ModelContainer) {
        let actor = TransactionActor(modelContainer: modelContainer)
        repo = actor
        transactions = TransactionListViewModel(repo: actor)
        dashboard = DashboardViewModel(repo: actor)
        compass = CompassViewModel(repo: actor)
    }
}
