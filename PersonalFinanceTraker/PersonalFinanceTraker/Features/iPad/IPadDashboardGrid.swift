//
//  IPadDashboardGrid.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// The iPad Home screen: the same dashboard cards as iPhone, reflowed into an adaptive grid.
///
/// Deliberately has no detail pane. Home has no natural "detail" — a permanent second column
/// here would be empty except in the rare case a recent transaction is selected, which is the
/// dead-space problem this redesign exists to remove. Selecting a transaction opens the shared
/// inspector instead.
///
/// None of iPhone's tab-bar compensation (`safeAreaPadding(.bottom, 128)`, the 44pt top inset)
/// is copied here — there is no floating tab bar in this shell to compensate for.
struct IPadDashboardGrid: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(TransactionListViewModel.self) private var transactionListViewModel
    @Environment(DataChangedSignal.self) private var dataChanged
    @Binding var showingAddItemView: Bool

    // iPad portrait and landscape column sizing:
    // - Landscape ~1200pt: 360pt min supports 3+ columns, but 560pt max constrains to ~2 full-width
    // - Portrait ~500pt: 360pt min forces 1 column; lowering to 280 gives ~2*280+20=580 ≈ fits portrait
    // Derived from typical iPad split-view widths (sidebar ~300-400pt, content ~500-600pt portrait,
    // ~800-1200pt landscape). Empirical testing on device should verify landscape stays at 2 columns.
    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 560), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GreetingHeaderView()

                if let callout = viewModel.anomalyCallout,
                   viewModel.dailyCheckInStatus.isComplete {
                    AnomalyCalloutView(message: callout.message) {
                        viewModel.dismissAnomaly()
                    }
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    BalanceCardView()

                    if !viewModel.hasNoTransactions {
                        DailyLoggingHabitCard(
                            transactionStatus: viewModel.dailyLoggingStatus,
                            checkInStatus: viewModel.dailyCheckInStatus,
                            templates: viewModel.quickTransactionTemplates,
                            showsReminderPrompt: viewModel.showsReminderPrompt,
                            onAdd: { showingAddItemView = true },
                            onRepeat: { template in
                                Task {
                                    if await viewModel.repeatTemplate(template) {
                                        dataChanged.bump()
                                    }
                                }
                            },
                            onCompleteNoSpend: { viewModel.completeNoSpendCheckIn() },
                            onUndoNoSpend: { viewModel.undoNoSpendCheckIn() },
                            onSetReminder: {
                                Task {
                                    if await ReminderService.shared.requestPermission() {
                                        viewModel.markReminderPromptAccepted()
                                    }
                                }
                            },
                            onDismissReminder: { viewModel.dismissReminderPrompt() }
                        )
                    }

                    if !viewModel.recentTransactions.isEmpty {
                        RecentTransactionsSectionView()
                    }
                }

                if !viewModel.nearLimitBudgets.isEmpty {
                    Text("NEAR BUDGET LIMIT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.textDim)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(viewModel.nearLimitBudgets) { progress in
                            BudgetProgressBarView(progress: progress) {
                                transactionListViewModel.selectedCategory = progress.categoryName
                            }
                        }
                    }
                }

                if viewModel.hasNoTransactions {
                    EmptyStateView(
                        icon: "plus.circle",
                        message: "Add your first transaction",
                        subtitle: "Track an expense or income to see your balance grow.",
                        actionTitle: "Add Transaction",
                        action: { showingAddItemView = true }
                    )
                }
            }
            .padding(24)
        }
        .navigationTitle("Home")
        .appBackground()
        .task { viewModel.load() }
    }
}
