//
//  InsightsView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData
import Charts

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
                    GoalsSection(
                        goals: viewModel.goals,
                        showingAddGoal: $viewModel.showingAddGoal,
                        transferTotal: viewModel.transferTotal(for:),
                        onSelectGoal: { viewModel.selectedGoal = $0 },
                        onDeleteGoal: viewModel.deleteGoal
                    )
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
                        )
                    )
                    SpendingTimelineChart(
                        selectedPeriod: $viewModel.selectedTimePeriod,
                        data: viewModel.timelineData
                    )
                    CategoryTrendsSection(trends: viewModel.categoryTrends)
                    HabitsSection(observations: viewModel.habitObservations)
                    ForecastSection(forecast: viewModel.forecast)
                    Spacer(minLength: 80)
                }
                .padding(16)
            }
            .appBackground()
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
            .appToolbar(showingAddItemView: $showingAddItemView)
        }
        .payCycleAware { viewModel.load() }
        .onAppear { viewModel.load() }
        .onChange(of: showingAddItemView) { _, isShowing in
            if !isShowing { viewModel.load() }
        }
        .sheet(isPresented: $viewModel.showingAddGoal) {
            NavigationStack {
                AddGoalSheet { viewModel.addGoal($0) }
            }
            .presentationDetents([.large])
            .presentationBackground { AppBackground() }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.goalEditDraft != nil },
            set: { if !$0 { viewModel.goalEditDraft = nil; viewModel.goalEditId = nil } }
        )) {
            NavigationStack {
                AddGoalSheet(initialGoalInput: viewModel.goalEditDraft) { input in
                    viewModel.goalEditDraft = input
                    viewModel.saveGoalEdits()
                }
            }
            .presentationDetents([.large])
            .presentationBackground { AppBackground() }
        }
        .sheet(item: $viewModel.selectedGoal) { goal in
            GoalDetailSheet(goal: goal, viewModel: viewModel) {
                viewModel.selectedGoal = nil
                viewModel.beginEditingGoal(goal)
            }
            .presentationDetents([.large])
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
        .preferredColorScheme(.dark)
}

#Preview { compassPreview() }
