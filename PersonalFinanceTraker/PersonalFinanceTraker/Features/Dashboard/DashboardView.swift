//
//  DashboardView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(TransactionListViewModel.self) private var transactionListViewModel
    @Environment(DataChangedSignal.self) private var dataChanged
    @Binding var showingAddItemView: Bool
    @Binding var selectedTab: TabItem

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    GreetingHeaderView()
                    BalanceCardView()
                    if let callout = viewModel.anomalyCallout,
                       viewModel.dailyCheckInStatus.isComplete {
                        AnomalyCalloutView(message: callout.message) {
                            viewModel.dismissAnomaly()
                        }
                    }
                    if !viewModel.nearLimitBudgets.isEmpty {
                        Text("NEAR BUDGET LIMIT")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.textDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        GlassEffectContainer(spacing: 20) {
                            VStack(spacing: 20) {
                                ForEach(viewModel.nearLimitBudgets) { progress in
                                    BudgetProgressBarView(progress: progress) {
                                        transactionListViewModel.selectedCategory = progress.categoryName
                                        selectedTab = .activity
                                    }
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
                            onCompleteNoSpend: {
                                viewModel.completeNoSpendCheckIn()
                            },
                            onUndoNoSpend: {
                                viewModel.undoNoSpendCheckIn()
                            },
                            onSetReminder: {
                                Task {
                                    let granted = await ReminderService.shared.requestPermission()
                                    if granted {
                                        viewModel.markReminderPromptAccepted()
                                    }
                                }
                            },
                            onDismissReminder: {
                                viewModel.dismissReminderPrompt()
                            }
                        )
                    }
                    if !viewModel.recentTransactions.isEmpty {
                        RecentTransactionsSectionView()
                    }
                    Spacer(minLength: 80)
                }
                .padding(16)
            }
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 44) }
            .appBackground()
            .navigationBarTitleDisplayMode(.inline)
            .appToolbar(showingAddItemView: $showingAddItemView)
        }
        .task { viewModel.load() }
    }
}


#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    let repo = TransactionActor.make(container)
    let dashVM = DashboardViewModel(repo: repo)
        return DashboardView(showingAddItemView: .constant(false), selectedTab: .constant(.home))
        .environment(dashVM)
        .environment(TransactionListViewModel(repo: repo))
        .environment(ProfileViewModel())
        .environment(DataChangedSignal())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
