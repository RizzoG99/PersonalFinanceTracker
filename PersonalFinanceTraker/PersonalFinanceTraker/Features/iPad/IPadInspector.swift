//
//  IPadInspector.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// The one inspector every iPad section shares. What it shows is decided by whatever selection
/// state is currently set — there is no separate "what's in the inspector" variable to keep in
/// sync, which is why it can't disagree with the list it was opened from.
///
/// Add Transaction lands here too rather than in a sheet, so the ledger stays visible while
/// you're entering — the whole point on a screen this wide.
struct IPadInspector: View {
    let models: AppShellModels
    @Binding var showingAddItemView: Bool
    let pendingReceiptScan: ReceiptScan?

    var body: some View {
        NavigationStack {
            content
        }
        .background { AppBackground() }
    }

    @ViewBuilder
    private var content: some View {
        if showingAddItemView {
            EditAddTransactionView(
                draft: nil,
                repo: models.repo,
                materializationService: models.materializationService,
                initialReceiptScan: pendingReceiptScan
            )
        } else if let item = models.transactions.transactionToEdit {
            // .id(item.id): without it, tapping a different row while the inspector is already
            // open reuses the existing EditAddTransactionView's identity, so its @State view
            // model — built once from the *first* item — never re-initializes from the new one.
            EditAddTransactionView(
                item,
                repo: models.repo,
                materializationService: models.materializationService
            )
            .id(item.id)
        } else if models.compass.showingAddGoal {
            AddGoalSheet { models.compass.addGoal($0) }
        } else if let draft = models.compass.goalEditDraft {
            AddGoalSheet(initialGoalInput: draft) { input in
                models.compass.goalEditDraft = input
                models.compass.saveGoalEdits()
            }
        } else if let goal = models.compass.selectedGoal {
            GoalDetailSheet(goal: goal, viewModel: models.compass) {
                models.compass.selectedGoal = nil
                models.compass.beginEditingGoal(goal)
            }
        } else {
            // Not reachable in normal use: `inspectorPresented` is false whenever none of the
            // above is set (showingAddItemView, transactionToEdit, showingAddGoal,
            // goalEditDraft, or selectedGoal), so the inspector is collapsed rather than
            // showing this.
            ContentUnavailableView(
                "Nothing Selected",
                systemImage: "sidebar.right"
            )
        }
    }
}
