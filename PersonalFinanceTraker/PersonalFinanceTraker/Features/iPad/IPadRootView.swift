//
//  IPadRootView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

/// The iPad shell: a persistent sidebar instead of the iPhone's floating tab bar, and a single
/// shared inspector instead of a permanent detail column.
///
/// The inspector is the important choice here. A fixed third column sits empty whenever nothing
/// is selected, which is most of the time — `.inspector()` collapses instead, so the content
/// column gets the full width until there is actually something to show in it.
struct IPadRootView: View {
    @Environment(FeatureDiscoveryCoordinator.self) private var featureDiscovery

    let models: AppShellModels
    let appSettings: AppSettings

    /// Optional because that's the only `List(selection:)` shape iOS offers; nil is treated as
    /// Home rather than as an empty content column.
    @State private var section: IPadSection? = .home
    @State private var showingAddItemView = false
    /// ProfileView takes this binding to drive its own sheet detents on iPhone. As a sidebar
    /// destination there is no sheet to size, so nothing observes it — it just satisfies the API.
    @State private var profileDetent: PresentationDetent = .large

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            content
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: inspectorPresented) {
            IPadInspector(models: models, showingAddItemView: $showingAddItemView)
                .inspectorColumnWidth(min: 320, ideal: 400, max: 560)
        }
        .background { AppBackground() }
        // On iPhone these hang off AppToolbarModifier, which the iPad shell suppresses. Settings
        // is a sidebar destination here, so the import flow it starts needs a host that outlives
        // the section switch — this one.
        .sheet(isPresented: importFlowPresented) {
            IPadImportFlowView(viewModel: models.transactions)
        }
        .alert("Import", isPresented: importErrorPresented) {
            Button("OK") { models.transactions.importError = nil }
        } message: {
            Text(models.transactions.importError ?? "")
        }
        // Same wiring MainTabView has: saving anywhere bumps the signal, and every shell has to
        // reload off it or the cards and lists keep showing pre-save data.
        .onChange(of: models.dataChanged.revision) { _, _ in
            models.dashboard.reload()
            models.transactions.reload()
            Task {
                await models.compass.reloadData()
                await HabitSnapshotUpdater.refresh(using: models.repo)
                await models.repo.refreshSafeToSpendWidgetSnapshot()
            }
        }
        .task {
            models.transactions.onDataChanged = { models.dataChanged.bump() }
            models.compass.onDataChanged = { models.dataChanged.bump() }
            models.transactions.load()
            try? await models.materializationService.materialize(using: models.repo)
            await HabitSnapshotUpdater.refresh(using: models.repo)
            await models.repo.refreshSafeToSpendWidgetSnapshot()
            models.dataChanged.bump()
            consumeFeatureDiscoveryDestination()
        }
        .onChange(of: featureDiscovery.pendingDestination) { _, destination in
            if destination != nil { consumeFeatureDiscoveryDestination() }
        }
        // Outermost, and it has to stay that way: a .sheet or .inspector attached further out than
        // these would present its content outside this environment, and anything reading
        // TransactionListViewModel / DataChangedSignal from it traps at runtime. That's exactly
        // how the import flow crashed on Continue.
        .environment(models.transactions)
        .environment(models.dashboard)
        .environment(models.profile)
        .environment(models.dataChanged)
        .environment(appSettings)
        .tint(Color.accentIndigo)
    }

    private var importFlowPresented: Binding<Bool> {
        Binding(
            get: { models.transactions.showingImportFlow },
            set: { models.transactions.showingImportFlow = $0 }
        )
    }

    private var importErrorPresented: Binding<Bool> {
        Binding(
            get: { models.transactions.importError != nil },
            set: { if !$0 { models.transactions.importError = nil } }
        )
    }

    private func consumeFeatureDiscoveryDestination() {
        guard let destination = featureDiscovery.consumeDestination() else { return }
        switch destination {
        case .activity:
            section = .activity
        case .insights:
            section = .insights
        case .home, .budgets:
            section = .home
        case .addTransaction:
            section = .home
            showingAddItemView = true
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $section) {
            ForEach(IPadSection.Group.allCases) { group in
                Section(group.title) {
                    ForEach(group.sections) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
            }
            Section {
                Label(IPadSection.settings.title, systemImage: IPadSection.settings.systemImage)
                    .tag(IPadSection.settings)
            }
        }
        .navigationTitle("Finance")
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add transaction", systemImage: "plus") {
                    showingAddItemView = true
                }
                .keyboardShortcut("n")
            }
        }
        .keyboardAction(",", title: "Settings") { section = .settings }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch section ?? .home {
        case .home:
            IPadDashboardGrid(showingAddItemView: $showingAddItemView)
        case .activity:
            IPadLedgerTable(showingAddItemView: $showingAddItemView)
        case .goals:
            IPadGoalsView(viewModel: models.compass)
        case .insights:
            CompassView(viewModel: models.compass, showingAddItemView: $showingAddItemView)
        case .healthScore:
            IPadHealthScoreView(viewModel: models.compass)
        case .settings:
            NavigationStack {
                ProfileView(viewModel: models.profile, selectedDetent: $profileDetent, isHostedAsSheet: false)
                    .navigationTitle("Settings")
                    .appBackground()
            }
        }
    }

    // MARK: - Inspector presentation

    /// Derived from the selection state the view models already own, rather than a separate
    /// `@State` flag that could fall out of sync with them. Setting it false clears whatever
    /// was selected, which is what the inspector's own dismiss control expects to happen.
    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: {
                showingAddItemView
                    || models.transactions.transactionToEdit != nil
                    || models.compass.showingAddGoal
                    || models.compass.goalEditDraft != nil
                    || models.compass.selectedGoal != nil
            },
            set: { presented in
                guard !presented else { return }
                showingAddItemView = false
                models.transactions.transactionToEdit = nil
                models.compass.showingAddGoal = false
                models.compass.goalEditDraft = nil
                models.compass.goalEditId = nil
                models.compass.selectedGoal = nil
            }
        )
    }
}
