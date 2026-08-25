//
//  RecurringView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

/// Lists every recurrence *rule* — not the transactions it produced. This screen answers "what
/// am I committed to", the same job as the reference app's own recurring list: tap a rule to
/// edit its definition, swipe to stop it. Finding the transactions a rule already produced is
/// the Activity tab's job (the Recurring filter chip), not this screen's — see issue #58.
///
/// Presented as a sheet that owns its own nested edit/add sheets (iPhone, and iPad's Activity
/// toolbar entry) — see `IPadRecurringSection` for the iPad sidebar destination, which is the
/// same list wired to the shared inspector instead.
struct RecurringView: View {
    @Environment(TransactionListViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    let materializationService: RecurrenceMaterializationService

    @State private var rules: [RecurrenceRuleSnapshot] = []
    @State private var showingAddSheet = false
    // Owned locally rather than routed through viewModel.transactionToEdit (the root-level sheet
    // MainTabView/IPadInspector present) so editing stacks *on top of* this screen instead of
    // dismissing it first — this screen is itself presented as a sheet, and a sheet can present a
    // child sheet of its own.
    @State private var editingItem: TransactionSnapshot?

    private func reloadRules() async {
        rules = (try? await viewModel.repo.fetchAllRecurrenceRules()) ?? []
    }

    /// Stops future occurrences only — deliberately does NOT touch any already-materialized
    /// transaction. "Delete" here means "I'm done with this commitment", not "erase its history".
    private func stopRecurrence(_ rule: RecurrenceRuleSnapshot) {
        Task {
            try? await viewModel.repo.closeRecurrenceRule(id: rule.id, endDate: .now)
            rules.removeAll { $0.id == rule.id }
        }
    }

    var body: some View {
        RecurringRulesContent(rules: rules, onSelect: { editingItem = $0 }, onDelete: stopRecurrence)
            .navigationTitle("Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Now that this screen is always a sheet (iPhone included — see the two call
                // sites), there's no back button to fall back on; give it an explicit close like
                // the Add sheet.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "Add Recurring Transaction"))
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                NavigationStack {
                    EditAddTransactionView(repo: viewModel.repo, materializationService: materializationService, presetRecurring: true)
                }
                .presentationBackground { AppBackground() }
            }
            .sheet(item: $editingItem) { item in
                NavigationStack {
                    EditAddTransactionView(item, repo: viewModel.repo, materializationService: materializationService)
                }
                .presentationBackground { AppBackground() }
            }
            .onChange(of: showingAddSheet) { _, isPresented in
                if !isPresented { Task { await reloadRules() } }
            }
            .onChange(of: editingItem) { _, item in
                if item == nil { Task { await reloadRules() } }
            }
            .task { await reloadRules() }
    }
}

/// The iPad sidebar destination for the same list — a permanent content pane like Health Score,
/// rather than a sheet. Tapping a rule opens its most recent occurrence in the shared inspector
/// on the right (the same detail surface Activity's rows use), instead of a nested sheet.
///
/// ponytail: "+" still opens the shared add sheet plain (no Repeat pre-enabled, unlike
/// RecurringView's own) — presetting it here would mean threading a flag through
/// IPadRootView/IPadInspector for one button; add it if that turns out to matter.
struct IPadRecurringSection: View {
    @Environment(TransactionListViewModel.self) private var viewModel
    let materializationService: RecurrenceMaterializationService

    @State private var rules: [RecurrenceRuleSnapshot] = []

    private func reloadRules() async {
        rules = (try? await viewModel.repo.fetchAllRecurrenceRules()) ?? []
    }

    private func stopRecurrence(_ rule: RecurrenceRuleSnapshot) {
        Task {
            try? await viewModel.repo.closeRecurrenceRule(id: rule.id, endDate: .now)
            rules.removeAll { $0.id == rule.id }
        }
    }

    var body: some View {
        RecurringRulesContent(
            rules: rules,
            onSelect: { viewModel.transactionToEdit = $0 },
            onDelete: stopRecurrence
        )
        .navigationTitle("Recurring")
        .task { await reloadRules() }
        // The inspector's edit sheet closing is the only thing that can change a rule's
        // note/amount/cadence here (there's no local add/edit sheet to key off), so refresh
        // whenever it clears.
        .onChange(of: viewModel.transactionToEdit) { _, item in
            if item == nil { Task { await reloadRules() } }
        }
    }
}

/// The rule list itself — stat header, rows, swipe-to-delete, empty state. Shared by both hosts
/// above, which differ only in how "tap a rule" and "delete a rule" are wired up: purely
/// presentational, so it owns no navigation of its own.
private struct RecurringRulesContent: View {
    @Environment(TransactionListViewModel.self) private var viewModel
    let rules: [RecurrenceRuleSnapshot]
    let onSelect: (TransactionSnapshot) -> Void
    let onDelete: (RecurrenceRuleSnapshot) -> Void

    private var categoryByPersistentId: [PersistentIdentifier: CategorySnapshot] {
        Dictionary(uniqueKeysWithValues: viewModel.availableCategories.map { ($0.persistentId, $0) })
    }

    private var activeRules: [RecurrenceRuleSnapshot] {
        rules.filter { $0.endDate == nil || $0.endDate! >= .now }
    }

    /// Same note + same cadence among active rules is almost certainly one series detected
    /// twice, not two real commitments — flagged rather than auto-merged, since merging means
    /// picking which rule's history and cursor survive.
    private var duplicateRuleIDs: Set<UUID> {
        let groups = Dictionary(grouping: activeRules) { "\($0.note.lowercased())#\($0.frequency.rawValue)#\($0.interval)" }
        return Set(groups.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) })
    }

    /// Expense rules only, normalized to a monthly-equivalent amount. A recurring paycheck isn't
    /// a "commitment" the same way a subscription is, and netting it in would understate the
    /// number this header exists to answer: how much recurring spend am I locked into.
    private var monthlyRecurringSpend: Decimal {
        activeRules
            .filter { $0.amount < 0 }
            .reduce(Decimal(0)) { $0 + monthlyEquivalent($1) }
    }

    private func monthlyEquivalent(_ rule: RecurrenceRuleSnapshot) -> Decimal {
        guard rule.interval > 0 else { return 0 }
        let interval = Decimal(rule.interval)
        switch rule.frequency {
        case .monthly: return rule.amount / interval
        case .weekly: return rule.amount * 52 / 12 / interval
        case .yearly: return rule.amount / 12 / interval
        }
    }

    /// The most recent occurrence a rule produced, used as the anchor for "edit this rule". It
    /// routes through the existing transaction edit sheet's "This and future" path, which already
    /// updates the rule's template — and anchoring on the *latest* row means that path's
    /// this-and-future delete/edit scope never reaches past it, minimizing blast radius.
    private func latestOccurrence(for rule: RecurrenceRuleSnapshot) -> TransactionSnapshot? {
        viewModel.transactions
            .filter { $0.recurrenceRuleId == rule.id }
            .max { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        Group {
            if rules.isEmpty {
                // EmptyStateView is a compact card — without an explicit fill, this Group (and the
                // .appBackground() below) only paints behind the card itself, leaving the rest of
                // the canvas as the system's default white on iPad's form-sheet style.
                EmptyStateView(
                    icon: "repeat",
                    message: "No recurring transactions yet",
                    subtitle: "Rules you add manually, or accept from an import, show up here."
                )
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 24)
            } else {
                List {
                    Section {
                        HStack(spacing: 12) {
                            StatCard(icon: "repeat", label: "Active", value: "\(activeRules.count)", color: .accentIndigo)
                            StatCard(icon: "calendar", label: "Monthly spend", value: monthlyRecurringSpend.formattedEUR(), color: .negative)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listSectionSeparator(.hidden)

                    ForEach(rules) { rule in
                        let anchor = latestOccurrence(for: rule)
                        Button {
                            guard let anchor else { return }
                            onSelect(anchor)
                        } label: {
                            ruleRow(rule, isEditable: anchor != nil)
                        }
                        .buttonStyle(.plain)
                        .disabled(anchor == nil)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                onDelete(rule)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // Insurance against the floating tab bar clipping the final row — List already
                // insets for system chrome, but this keeps the last row's tap target clear of it.
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 12) }
            }
        }
        .appBackground()
    }

    private func ruleRow(_ rule: RecurrenceRuleSnapshot, isEditable: Bool) -> some View {
        let mapped = rule.categoryId.flatMap { categoryByPersistentId[$0] }
        let symbol = mapped?.systemImage ?? CategoryInfo.info(for: rule.category).symbol
        let tint = mapped.map { Color(categoryToken: $0.colorToken) } ?? CategoryInfo.info(for: rule.category).color

        return HStack(spacing: 10) {
            GlassCard(tint: tint.opacity(0.12), borderRadius: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14, height: 14)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(rule.note)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.textPrimary)
                    if duplicateRuleIDs.contains(rule.id) {
                        Text("Possible duplicate")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.categoryAmber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.categoryAmber.opacity(0.15), in: .capsule)
                    }
                }
                Text(cadenceSubtitle(for: rule, isEditable: isEditable))
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }

            Spacer()

            Text(rule.amount, format: .currency(code: rule.currencyCode).sign(strategy: .always()))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(rule.amount >= 0 ? .positive : .negative)
                .privacyBlur()
        }
        .padding(.vertical, 4)
        // Nothing to anchor an edit on yet (its one transaction was deleted "this only", and the
        // next materialization pass hasn't run) — dim rather than open a broken edit flow.
        .opacity(isEditable ? 1 : 0.5)
        .contentShape(Rectangle())
    }

    private func cadenceSubtitle(for rule: RecurrenceRuleSnapshot, isEditable: Bool) -> String {
        let cadence = rule.frequency.cadenceLabel(interval: rule.interval)
        if let endDate = rule.endDate, endDate < .now {
            return cadence + " · " + String(localized: "Ended \(endDate.formatted(date: .abbreviated, time: .omitted))")
        }
        if !isEditable {
            return cadence + " · " + String(localized: "No transactions yet")
        }
        let next = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: rule.frequency,
            interval: rule.interval,
            startDate: rule.startDate,
            ruleEndDate: rule.endDate,
            since: .now,
            through: Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
        ).first
        guard let next else { return cadence }
        return cadence + " · " + String(localized: "next \(next.formatted(date: .abbreviated, time: .omitted))")
    }
}
