//
//  InsightsView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData
import Charts

struct CompassView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CompassViewModel
    @Binding var showingAddItemView: Bool

    init(context: ModelContext, showingAddItemView: Binding<Bool>) {
        _viewModel = State(wrappedValue: CompassViewModel(repo: TransactionRepository(context: context)))
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
                    HealthScoreSection(healthScore: viewModel.healthScore)
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
            .navigationTitle("Compass")
            .navigationBarTitleDisplayMode(.large)
            .appToolbar(showingAddItemView: $showingAddItemView)
        }
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
        .sheet(item: $viewModel.goalToEdit) { goal in
            NavigationStack {
                AddGoalSheet(goal: goal) { _ in viewModel.saveGoalEdits() }
            }
            .presentationDetents([.large])
            .presentationBackground { AppBackground() }
        }
        .sheet(item: $viewModel.selectedGoal) { goal in
            GoalDetailSheet(goal: goal, viewModel: viewModel) {
                viewModel.selectedGoal = nil
                viewModel.goalToEdit = goal
            }
            .presentationDetents([.large])
            .presentationBackground { AppBackground() }
        }
    }
}

// MARK: - Preview

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self, CreditCardModel.self, GoalModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    return CompassView(context: container.mainContext, showingAddItemView: .constant(false))
        .environment(ProfileViewModel())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
