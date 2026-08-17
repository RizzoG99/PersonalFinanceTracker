//
//  IPadGoalsView.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// Goals as a destination in its own right. On iPhone this is one section buried in the middle
/// of the Insights scroll; on iPad it's somewhere you navigate to, so it gets the full width.
///
/// Selecting a goal sets `selectedGoal`, which the shared inspector picks up — no sheet.
struct IPadGoalsView: View {
    let viewModel: CompassViewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        return ScrollView {
            GoalsSection(
                goals: viewModel.goals,
                showingAddGoal: $viewModel.showingAddGoal,
                transferTotal: viewModel.transferTotal(for:),
                onSelectGoal: { viewModel.selectedGoal = $0 },
                onDeleteGoal: viewModel.deleteGoal
            )
            .padding(24)
        }
        .navigationTitle("Goals")
        .appBackground()
        .onAppear { viewModel.load() }
        // ponytail: iPad routes "Add Goal" through the shared inspector (showingAddGoal →
        // IPadInspector) rather than a sheet, keeping the goals list visible while entering.
        // The sheet is omitted here; GoalsSection still mutates showingAddGoal, and
        // IPadRootView.inspectorPresented responds to it.
    }
}
