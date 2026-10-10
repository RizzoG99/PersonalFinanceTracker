//
//  InsightsView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct CompassView: View {
    @State private var viewModel: CompassViewModel
    @Binding var showingAddItemView: Bool
    var onScanned: ((ReceiptScan) -> Void)? = nil

    init(viewModel: CompassViewModel, showingAddItemView: Binding<Bool>, onScanned: ((ReceiptScan) -> Void)? = nil) {
        _viewModel = State(wrappedValue: viewModel)
        _showingAddItemView = showingAddItemView
        self.onScanned = onScanned
    }

    private static let explorerId = "breakdown-explorer"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {
                    if let recap = viewModel.monthlyRecap {
                        MonthlyRecapCard(recap: recap) {
                            let last = Calendar.current.date(byAdding: .day, value: -1, to: recap.cycleEnd) ?? recap.cycleEnd
                            viewModel.explorerPeriod = .custom(from: recap.cycleStart, through: last)
                            // The explorer can be below the fold (small screen, large text):
                            // bring it up so the tap visibly does something.
                            withAnimation { proxy.scrollTo(Self.explorerId, anchor: .top) }
                        }
                    }
                    BreakdownExplorerSection(viewModel: viewModel)
                        .id(Self.explorerId)
                    HealthScoreSection(
                        healthScore: viewModel.healthScore,
                        snapshots: viewModel.scoreSnapshots,
                        payCycleStartDay: AppSettings.storedStartDay,
                        ignoreSubscriptions: Binding(
                            get: { viewModel.ignoreSubscriptions },
                            set: { viewModel.ignoreSubscriptions = $0 }
                        ),
                        showingDetail: $viewModel.showingHealthScoreDetail
                    )
                    HabitsSection(observations: viewModel.habitObservations)
                }
                .padding(16)
            }
            }
            .navigationDestination(for: ExplorerDrillDown.self) { drillDown in
                CategoryTransactionsView(drillDown: drillDown, viewModel: viewModel)
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
            .appToolbar(showingAddItemView: $showingAddItemView, onScanned: onScanned)
            .appBackground()
        }
        .payCycleAware { viewModel.load() }
        .onAppear { viewModel.load() }
        .onChange(of: showingAddItemView) { _, isShowing in
            if !isShowing { viewModel.load() }
        }
    }
}

// MARK: - Preview

// Hoisted out of #Preview: the macro expansion trips a type-checker crash on TransactionActor construction
@MainActor private func compassPreview() -> some View {
    let schema = Schema([TransactionModel.self, CategoryModel.self, CreditCardModel.self, GoalModel.self, TravelModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    let repo: any ITransactionRepository = TransactionActor(modelContainer: container)
    return CompassView(
        viewModel: CompassViewModel(repo: repo),
        showingAddItemView: .constant(false)
    )
        .environment(ProfileViewModel())
        .modelContainer(container)
}

#Preview { compassPreview() }
