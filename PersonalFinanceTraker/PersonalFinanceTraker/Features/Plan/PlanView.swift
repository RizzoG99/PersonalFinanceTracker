//
//  PlanView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

/// The Plan tab (#187): "what's coming / what I want". Upcoming recurring charges, every budget
/// and the goals, on one page. iPhone only — the iPad sidebar gives each its own destination.
struct PlanView: View {
    let compassViewModel: CompassViewModel
    let materializationService: RecurrenceMaterializationService
    @Binding var showingAddItemView: Bool
    /// Owned by MainTabView so Feature Discovery's "Open Recurring" can open it from anywhere.
    @Binding var showingRecurringView: Bool
    @Binding var selectedTab: TabItem
    var onScanned: ((ReceiptScan) -> Void)? = nil

    @Environment(TransactionListViewModel.self) private var transactionListViewModel
    @Environment(DashboardViewModel.self) private var dashboardViewModel
    @Environment(DataChangedSignal.self) private var dataChanged

    @State private var rules: [RecurrenceRuleSnapshot] = []
    /// False until rules and goals have both loaded once, so a store that has data doesn't
    /// flash the all-empty welcome state first.
    @State private var hasLoaded = false
    @State private var showingAddRecurring = false
    @State private var editingRule: RecurrenceRuleSnapshot?
    @State private var showingBudgets = false
    @State private var committedSpending = CommittedSpendingModel()

    private var upcoming: [UpcomingCharge] { UpcomingCharge.timeline(rules: rules) }
    /// Rules not yet stopped (e.g. "Stopped paying", #188, ends one): a store with only stopped
    /// rules gets the "No recurring payments" empty state, not "Nothing due".
    private var hasActiveRules: Bool {
        let today = Calendar.current.startOfDay(for: .now)
        return rules.contains { $0.endDate.map { $0 >= today } ?? true }
    }
    /// The timeline by day (#189), empty days left out.
    private var upcomingDays: [(day: Date, charges: [UpcomingCharge])] {
        Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.date) }
            .map { (day: $0.key, charges: $0.value) }
            .sorted { $0.day < $1.day }
    }
    private var budgets: [BudgetProgress] { dashboardViewModel.budgetProgress }
    private var goals: [GoalSnapshot] { compassViewModel.goals }

    var body: some View {
        @Bindable var compass = compassViewModel
        NavigationStack {
            ScrollView {
                if !hasLoaded {
                    // Full width: the ScrollView sizes to its content, and `.appBackground()` sits on
                    // the ScrollView — a bare spinner left the gradient a ~20pt strip on a black screen.
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if !hasActiveRules && budgets.isEmpty && goals.isEmpty {
                    // A store with history but no plan yet is exactly where fixed expenses get found.
                    if !committedSpending.isEmpty {
                        FixedExpensesSection(model: committedSpending)
                            .padding(16)
                    }
                    welcome
                } else {
                    LazyVStack(spacing: 24) {
                        if !committedSpending.isEmpty {
                            FixedExpensesSection(model: committedSpending)
                        }
                        recurringSection
                        budgetsSection
                        GoalsSection(
                            goals: goals,
                            showingAddGoal: $compass.showingAddGoal,
                            transferTotal: compassViewModel.transferTotal(for:),
                            onSelectGoal: { compassViewModel.selectedGoal = $0 },
                            onDeleteGoal: compassViewModel.deleteGoal
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showingBudgets) {
                BudgetsView()
                    .appBackground()
            }
            .appToolbar(showingAddItemView: $showingAddItemView, onScanned: onScanned)
            .fixedExpenseFeedback(committedSpending)
            .appBackground()
        }
        .task(id: dataChanged.revision) {
            // Goals live on CompassViewModel, which nothing else loads at launch on iPhone until
            // Insights opens — load it here too, or Plan reads an existing goal list as empty.
            async let goals: Void = compassViewModel.reloadData()
            // A matched payment moves a rule's cursor: bump once so Coming up re-reads it (the
            // second pass finds nothing new to match).
            if await committedSpending.reload(repo: transactionListViewModel.repo) {
                dataChanged.bump()
            }
            await reloadRules()
            await goals
            hasLoaded = true
        }
        // BudgetsView edits CategoryModel directly (no dataChanged bump), so refresh the bars
        // on the way back from it.
        .onChange(of: showingBudgets) { _, isShowing in
            if !isShowing { dashboardViewModel.reload() }
        }
        // A sheet, not a push: RecurringView owns its own nested edit sheet, so tapping a rule
        // there stacks the edit surface on top instead of popping back here first.
        .sheet(isPresented: $showingRecurringView, onDismiss: { Task { await reloadRules() } }) {
            NavigationStack {
                RecurringView(materializationService: materializationService)
            }
            .presentationBackground { AppBackground() }
        }
        .sheet(item: $editingRule, onDismiss: { Task { await reloadRules() } }) { rule in
            NavigationStack {
                EditAddTransactionView(rule: rule, repo: transactionListViewModel.repo, materializationService: materializationService)
            }
            .presentationBackground { AppBackground() }
        }
        .sheet(isPresented: $showingAddRecurring, onDismiss: { Task { await reloadRules() } }) {
            NavigationStack {
                EditAddTransactionView(repo: transactionListViewModel.repo, materializationService: materializationService, presetRecurring: true)
            }
            .presentationBackground { AppBackground() }
        }
        .sheet(isPresented: $compass.showingAddGoal) {
            NavigationStack {
                AddGoalSheet { compassViewModel.addGoal($0) }
            }
            .presentationBackground { AppBackground() }
        }
        .sheet(isPresented: Binding(
            get: { compassViewModel.goalEditDraft != nil },
            set: { if !$0 { compassViewModel.goalEditDraft = nil; compassViewModel.goalEditId = nil } }
        )) {
            NavigationStack {
                AddGoalSheet(initialGoalInput: compassViewModel.goalEditDraft) { input in
                    compassViewModel.goalEditDraft = input
                    compassViewModel.saveGoalEdits()
                }
            }
            .presentationBackground { AppBackground() }
        }
        .sheet(item: $compass.selectedGoal) { goal in
            GoalDetailSheet(goal: goal, viewModel: compassViewModel) {
                compassViewModel.selectedGoal = nil
                compassViewModel.beginEditingGoal(goal)
            }
            .presentationBackground { AppBackground() }
        }
    }

    private func reloadRules() async {
        rules = (try? await transactionListViewModel.repo.fetchAllRecurrenceRules()) ?? []
    }

    // MARK: - Sections

    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Coming up", subtitle: "Next 14 days") {
                Button("See all") { showingRecurringView = true }
            }
            if !hasActiveRules {
                EmptyStateView(
                    icon: "repeat",
                    message: "No recurring payments",
                    subtitle: "Add rent, subscriptions or bills to see them coming.",
                    actionTitle: "Add recurring payment",
                    action: { showingAddRecurring = true }
                )
            } else if upcoming.isEmpty {
                GlassCard {
                    Text("Nothing due in the next 14 days.")
                        .font(.subheadline)
                        .foregroundStyle(.textMid)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                let totals = UpcomingCharge.totals(upcoming)
                Text("In \(totals.inflow.formattedEUR()) · Out \(totals.outflow.formattedEUR())")
                    .font(.subheadline.bold())
                    .foregroundStyle(.textMid)
                    .privacyBlur()
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(upcomingDays, id: \.day) { group in
                            Text(UpcomingChargeRow.dayLabel(for: group.day))
                                .font(.caption.bold())
                                .foregroundStyle(.textDim)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.charges) { charge in
                                // Opens the rule itself (same edit surface as "See all"), not one
                                // occurrence — the row is about the commitment.
                                Button { editingRule = charge.rule } label: {
                                    UpcomingChargeRow(charge: charge)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Edits this recurring payment")
                            }
                            if group.day != upcomingDays.last?.day {
                                Divider()
                                    .padding(.horizontal, -16)
                            }
                        }
                    }
                }
            }
        }
    }

    private var budgetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Budgets", subtitle: "This cycle, per category") {
                Button("Manage") { showingBudgets = true }
            }
            if budgets.isEmpty {
                EmptyStateView(
                    icon: "chart.bar",
                    message: "No budgets yet",
                    subtitle: "Set a monthly limit on a category to track it here.",
                    actionTitle: "Create budget",
                    action: { showingBudgets = true }
                )
            } else {
                GlassEffectContainer(spacing: 20) {
                    VStack(spacing: 12) {
                        ForEach(budgets) { progress in
                            // Same as Home's bars: tap shows that category's transactions.
                            BudgetProgressBarView(progress: progress) {
                                transactionListViewModel.selectedCategory = progress.categoryName
                                selectedTab = .activity
                            }
                        }
                    }
                }
            }
        }
    }

    private var welcome: some View {
        ContentUnavailableView {
            Label("Plan what's ahead", systemImage: "calendar")
        } description: {
            Text("See your next recurring payments, keep budgets in check and save toward goals — all in one place.")
        } actions: {
            Button("Add recurring payment") { showingAddRecurring = true }
                .buttonStyle(.borderedProminent)
            Button("Create budget") { showingBudgets = true }
            Button("Add goal") { compassViewModel.showingAddGoal = true }
        }
        .tint(.accentIndigo)
        .padding(.top, 40)
    }

    /// Same header shape as GoalsSection's, with a quieter text action on the trailing side.
    private func sectionHeader(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder action: () -> some View
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
            Spacer()
            action()
                .font(.subheadline.bold())
                .tint(.accentIndigo)
                .frame(minHeight: 44)
        }
    }
}

// MARK: - Preview

@MainActor private func planPreview() -> some View {
    let schema = Schema([TransactionModel.self, CategoryModel.self, CreditCardModel.self, GoalModel.self, TravelModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    let models = AppShellModels(modelContainer: container)
    return PlanView(
        compassViewModel: models.compass,
        materializationService: models.materializationService,
        showingAddItemView: .constant(false),
        showingRecurringView: .constant(false),
        selectedTab: .constant(.plan)
    )
    .environment(models.transactions)
    .environment(models.dashboard)
    .environment(models.dataChanged)
    .environment(ProfileViewModel())
    .modelContainer(container)
}

#Preview { planPreview() }
