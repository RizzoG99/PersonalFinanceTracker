//
//  MainTabView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(FeatureDiscoveryCoordinator.self) private var featureDiscovery
    @AppStorage("app_base_currency") private var baseCurrency: String = Locale.current.currency?.identifier ?? "EUR"
    @AppStorage("pending_widget_destination") private var pendingWidgetDestination = ""
    // Seeded from `AppShellModels.selectedTab` and written back on change (below), so the tab
    // the user was on survives the shell being torn down and rebuilt on lock/unlock.
    @State private var selectedTab: TabItem
    @State private var showingAddItemView: Bool = false
    @State private var pendingTransactionDraft: TransactionDraft?
    /// Set once AppToolbarModifier's "Scan receipt" button finishes its own capture+recognition
    /// flow (see ReceiptScanShortcut) — carried into the Add Transaction sheet, which then opens
    /// already filled in.
    @State private var pendingReceiptScan: ReceiptScan?
    @State private var viewModel: TransactionListViewModel
    @State private var dashboardViewModel: DashboardViewModel
    @State private var compassViewModel: CompassViewModel
    @State private var profileViewModel: ProfileViewModel
    @State private var dataChanged: DataChangedSignal
    private let repo: TransactionActor
    private let materializationService: RecurrenceMaterializationService
    // Owned by AuthenticationWrapper (not MainTabView) so hideAmounts survives the
    // background→lock→foreground cycle: MainTabView itself is torn down and recreated
    // every time the PIN/biometric lock screen shows, which would otherwise reset it.
    private let appSettings: AppSettings
    /// Kept only to write `selectedTab` back on change — everything else comes from it up front,
    /// into this view's own `@State`, same as the other models below.
    private let shellModels: AppShellModels

    /// View models come from the shared `AppShellModels` rather than being built here, so the
    /// iPad shell binds to the very same instances (see AppShellModels).
    init(models: AppShellModels, appSettings: AppSettings) {
        repo = models.repo
        materializationService = models.materializationService
        self.appSettings = appSettings
        shellModels = models
        _selectedTab = State(wrappedValue: models.selectedTab)
        _viewModel = State(wrappedValue: models.transactions)
        _dashboardViewModel = State(wrappedValue: models.dashboard)
        _compassViewModel = State(wrappedValue: models.compass)
        _profileViewModel = State(wrappedValue: models.profile)
        _dataChanged = State(wrappedValue: models.dataChanged)
    }

    private func applyScan(_ scan: ReceiptScan) {
        pendingReceiptScan = scan
        showingAddItemView = true
    }

    private func consumePendingAdd() {
        if PendingTransactionIntent.shared.consume(isEditSheetOpen: viewModel.transactionToEdit != nil)
            || PendingHabitAddStore.consume() {
            showingAddItemView = true
        }
    }

    private func consumeFeatureDiscoveryDestination() {
        guard let destination = featureDiscovery.consumeDestination() else { return }
        switch destination {
        case .activity:
            selectedTab = .activity
        case .insights:
            selectedTab = .insights
        case .home, .budgets:
            selectedTab = .home
        case .addTransaction:
            selectedTab = .home
            showingAddItemView = true
        }
    }

    private func consumePendingHabitTemplate() {
        guard !showingAddItemView, viewModel.transactionToEdit == nil else { return }
        guard let request = PendingHabitTemplateStore.consume() else { return }
        PendingTransactionIntent.shared.shouldReviewHabitTemplate = false
        selectedTab = .home
        pendingTransactionDraft = request.transactionDraft
        showingAddItemView = true
    }

    private func consumePendingWidgetDestination() {
        guard pendingWidgetDestination == "insights" else { return }
        selectedTab = .insights
        pendingWidgetDestination = ""
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: selectedTab == .home ? "house.fill" : "house", value: .home) {
                    DashboardView(showingAddItemView: $showingAddItemView, selectedTab: $selectedTab, onScanned: applyScan)
                        .payCycleAware { dashboardViewModel.load() }
                }
                Tab("Activity", systemImage: selectedTab == .activity ? "list.bullet.rectangle.fill" : "list.bullet.rectangle", value: .activity) {
                    ActivityView(showingAddItemView: $showingAddItemView, materializationService: materializationService, onScanned: applyScan)
                        .payCycleAware { viewModel.load() }
                }
                Tab("Insights", systemImage: "chart.line.uptrend.xyaxis", value: .insights) {
                    CompassView(viewModel: compassViewModel, showingAddItemView: $showingAddItemView, onScanned: applyScan)
                }
// Tab("Credit", systemImage: selectedTab == .credit ? "creditcard.fill" : "creditcard", value: .credit) {
//     CreditView(context: modelContext, showingAddItemView: $showingAddItemView)
// }
            }
            .environment(\.symbolVariants, .none)
            .tint(Color.accentIndigo)
            .environment(viewModel)
            .environment(dashboardViewModel)
            .environment(profileViewModel)
            .environment(appSettings)
            .environment(dataChanged)
            .sheet(isPresented: $showingAddItemView) {
                NavigationStack {
                    EditAddTransactionView(
                        draft: pendingTransactionDraft,
                        repo: repo,
                        materializationService: materializationService,
                        initialReceiptScan: pendingReceiptScan
                    )
                        .environment(dataChanged)
                        .environment(appSettings)
                }
                .presentationBackground { AppBackground() }
                .onDisappear {
                    pendingTransactionDraft = nil
                    pendingReceiptScan = nil
                    consumePendingHabitTemplate()
                }
            }
            .sheet(item: $viewModel.transactionToEdit) { item in
                NavigationStack {
                    EditAddTransactionView(item, repo: repo, materializationService: materializationService)
                        .environment(dataChanged)
                        .environment(appSettings)
                }
                .presentationBackground { AppBackground() }
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.showUndoBanner {
                UndoDeleteBanner(
                    message: viewModel.pendingUndoMessage,
                    progress: viewModel.deleteProgress,
                    onUndo: viewModel.undoPending
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.showUndoBanner)
        .hideAmountsShortcut(appSettings)
        .onChange(of: selectedTab) { _, newTab in
            shellModels.selectedTab = newTab
        }
        .onChange(of: viewModel.pendingDeletion) { _, pending in
            if !pending.isEmpty { dashboardViewModel.optimisticRemove(ids: pending.map(\.id)) }
        }
        .onChange(of: viewModel.showUndoBanner) { _, isShowing in
            if !isShowing { dashboardViewModel.reload() }
        }
        .onChange(of: dataChanged.revision) { _, _ in
            dashboardViewModel.reload()
            viewModel.reload()
            compassViewModel.load()
            Task {
                await HabitSnapshotUpdater.refresh(using: repo)
                await repo.refreshSafeToSpendWidgetSnapshot()
            }
        }
        .onChange(of: appSettings.payCycleStartDay) { _, _ in
            Task { await repo.refreshSafeToSpendWidgetSnapshot() }
        }
        .onChange(of: baseCurrency) { _, _ in
            Task { await repo.refreshSafeToSpendWidgetSnapshot() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await viewModel.commitPendingDeletion() }
            }
            if phase == .active {
                // Data may have changed outside the UI (App Intent quick-add)
                dashboardViewModel.reload()
                viewModel.reload()
                compassViewModel.load()
                Task {
                    try? await materializationService.materialize(using: repo)
                    await HabitSnapshotUpdater.refresh(using: repo)
                    await repo.refreshSafeToSpendWidgetSnapshot()
                    dataChanged.bump()
                }
            }
            if phase == .active {
                consumePendingHabitTemplate()
                consumePendingAdd()
            }
            if phase == .active || phase == .background {
                // ponytail: in-memory check may lag a just-saved transaction by one
                // phase change; the next foreground/background pass corrects it
                let checkInStatus = DailyCheckInService.computeStatus(
                    transactions: viewModel.transactions,
                    noSpendDateKeys: DailyCheckInStore.noSpendDateKeys()
                )
                ReminderService.shared.reschedule(hasCompletedToday: checkInStatus.isComplete)
            }
        }
        .task {
            viewModel.onDataChanged = { dataChanged.bump() }
            compassViewModel.onDataChanged = { dataChanged.bump() }
            viewModel.load()  // ponytail: pre-warm Activity while user is on Home; isLoaded guard makes repeat a no-op
            try? await materializationService.materialize(using: repo)
            await HabitSnapshotUpdater.refresh(using: repo)
            await repo.refreshSafeToSpendWidgetSnapshot()
            dataChanged.bump()
            consumePendingAdd()
            consumePendingHabitTemplate()
            consumePendingWidgetDestination()
        }
        .onChange(of: PendingTransactionIntent.shared.shouldPresentAdd) { _, pending in
            if pending { consumePendingAdd() }
        }
        .onChange(of: featureDiscovery.pendingDestination) { _, destination in
            if destination != nil { consumeFeatureDiscoveryDestination() }
        }
        .onChange(of: PendingTransactionIntent.shared.shouldReviewHabitTemplate) { _, pending in
            if PendingTransactionIntent.shared.consumeHabitTemplate(isSheetOpen: showingAddItemView), pending {
                consumePendingHabitTemplate()
            }
        }
        .onChange(of: pendingWidgetDestination) { _, destination in
            if destination == "insights" { consumePendingWidgetDestination() }
        }
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self, CreditCardModel.self, GoalModel.self])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    do {
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        SampleData.populateModelContext(container.mainContext)
        return MainTabView(models: AppShellModels(modelContainer: container), appSettings: AppSettings())
            .environment(FeatureDiscoveryCoordinator())
            .modelContainer(container)
    } catch {
        return Text("Failed to create preview container: \(error.localizedDescription)")
    }
}
