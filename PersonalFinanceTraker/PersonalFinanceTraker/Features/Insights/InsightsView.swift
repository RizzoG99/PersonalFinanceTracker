//
//  InsightsView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData
import Charts
import UIKit

struct CompassView: View {
    @State private var viewModel: CompassViewModel
    @Binding var showingAddItemView: Bool

    init(viewModel: CompassViewModel, showingAddItemView: Binding<Bool>) {
        _viewModel = State(wrappedValue: viewModel)
        _showingAddItemView = showingAddItemView
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // ponytail: Goals section is omitted on iPad where it has its own sidebar
                    // destination (IPadGoalsView). iPhone keeps it in Insights for compact
                    // horizontal scrolling through all insights at once.
                    if UIDevice.current.userInterfaceIdiom != .pad {
                        GoalsSection(
                            goals: viewModel.goals,
                            showingAddGoal: $viewModel.showingAddGoal,
                            transferTotal: viewModel.transferTotal(for:),
                            onSelectGoal: { viewModel.selectedGoal = $0 },
                            onDeleteGoal: viewModel.deleteGoal
                        )
                    }
                    if let insight = viewModel.heroInsight {
                        HeroInsightCard(insight: insight)
                    }
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
                    SpendingTimelineChart(
                        selectedPeriod: $viewModel.selectedTimePeriod,
                        data: viewModel.timelineData
                    )
                    CategoryTrendsSection(trends: viewModel.categoryTrends)
                    HabitsSection(observations: viewModel.habitObservations)
                    ForecastSection(forecast: viewModel.forecast)
                }
                .padding(16)
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
            .appToolbar(showingAddItemView: $showingAddItemView)
            .appBackground()
        }
        .payCycleAware { viewModel.load() }
        .onAppear { viewModel.load() }
        .onChange(of: showingAddItemView) { _, isShowing in
            if !isShowing { viewModel.load() }
        }
        // ponytail: On iPad, goal routing goes through the shared inspector (IPadInspector +
        // IPadRootView.inspectorPresented), which prevents duplicate presentations. iPhone
        // sheets fire normally here, preserving the existing experience and the close gesture.
        .sheet(isPresented: UIDevice.current.userInterfaceIdiom == .phone ? $viewModel.showingAddGoal : .constant(false)) {
            NavigationStack {
                AddGoalSheet { viewModel.addGoal($0) }
            }
            .presentationBackground { AppBackground() }
        }
        .sheet(isPresented: UIDevice.current.userInterfaceIdiom == .phone ? Binding(
            get: { viewModel.goalEditDraft != nil },
            set: { if !$0 { viewModel.goalEditDraft = nil; viewModel.goalEditId = nil } }
        ) : .constant(false)) {
            NavigationStack {
                AddGoalSheet(initialGoalInput: viewModel.goalEditDraft) { input in
                    viewModel.goalEditDraft = input
                    viewModel.saveGoalEdits()
                }
            }
            .presentationBackground { AppBackground() }
        }
        .sheet(item: UIDevice.current.userInterfaceIdiom == .phone ? $viewModel.selectedGoal : .constant(nil)) { goal in
            GoalDetailSheet(goal: goal, viewModel: viewModel) {
                viewModel.selectedGoal = nil
                viewModel.beginEditingGoal(goal)
            }
            .presentationBackground { AppBackground() }
        }
    }

}

// MARK: - Preview

// Hoisted out of #Preview: the macro expansion trips a type-checker crash on TransactionActor construction
@MainActor private func compassPreview() -> some View {
    let schema = Schema([TransactionModel.self, CategoryModel.self, CreditCardModel.self, GoalModel.self])
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
