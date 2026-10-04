//
//  FixedExpensesSection.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// A forecast-only rule whose payment never arrived (#188).
struct MissedPayment: Identifiable {
    var id: UUID { rule.id }
    let rule: RecurrenceRuleSnapshot
    let due: Date

    var title: String {
        rule.note.isEmpty ? rule.category.removingLeadingEmoji.localizedCategoryDisplay : rule.note
    }
}

extension RecurrenceSuggestion {
    var title: String {
        note.isEmpty ? category.removingLeadingEmoji.localizedCategoryDisplay : note
    }
}

/// A one-way answer ("Not fixed", "Stopped paying") held back for a few seconds so it can be
/// undone: the card is already gone, the write happens only when the toast expires.
struct PendingUndo: Identifiable {
    let id = UUID()
    let message: String
    let suggestionId: UUID?
    let ruleId: UUID?
    let commit: () async -> Void
    let restore: () -> Void
}

/// Committed-spending detection (#188) for Plan: fixed expenses found in the whole history,
/// waiting for a one-tap confirmation, and forecast-only rules whose payment didn't come.
@MainActor @Observable
final class CommittedSpendingModel {
    private(set) var suggestions: [RecurrenceSuggestion] = []
    private(set) var missed: [MissedPayment] = []
    private(set) var pendingUndo: PendingUndo?
    /// Bumped on every successful answer — drives the success haptic.
    private(set) var answeredCount = 0
    var errorMessage: String?

    var isEmpty: Bool { suggestions.isEmpty && missed.isEmpty }

    /// Returns true when it moved a rule's cursor, so the caller can tell Plan the rules changed.
    @discardableResult
    func reload(repo: any ITransactionRepository) async -> Bool {
        let transactions = (try? await repo.fetchAll()) ?? []
        var rules = (try? await repo.fetchActiveRecurrenceRules()) ?? []
        // Match payments first (the materializer only runs on launch/foreground): a bill that
        // just arrived by import must not show up below as missed.
        var advanced = false
        for rule in rules where !rule.autoRecord {
            guard let paid = RecurrenceDetector.paidThrough(rule: rule, transactions: transactions) else { continue }
            try? await repo.advanceRecurrenceRule(id: rule.id, cursor: paid.cursor, amount: paid.amount)
            advanced = true
        }
        if advanced { rules = (try? await repo.fetchActiveRecurrenceRules()) ?? rules }
        let dismissed = DismissedRecurrencePatterns.all
        let inputs = transactions.map(TransactionInput.init)
        // ponytail: recomputed from scratch on every data change — a personal ledger is a few
        // thousand rows; cache per revision if this ever shows up in a profile.
        let detected = await Task.detached(priority: .utility) {
            RecurrenceDetector.detect(in: inputs, existingRules: rules, dismissed: dismissed)
        }.value
        // An answer waiting out its undo toast isn't written yet — keep its card hidden.
        suggestions = detected.filter { RecurrenceDetector.dismissalPattern(for: $0) != pendingSuggestionPattern }
        missed = rules
            .filter { $0.id != pendingUndo?.ruleId }
            .compactMap { rule in RecurrenceDetector.missedOccurrence(rule: rule).map { MissedPayment(rule: rule, due: $0) } }
        return advanced
    }

    private var pendingSuggestionPattern: DismissedRecurrencePattern?

    // MARK: Answers — the card leaves first, so a second tap has nothing to hit (no duplicate rules).

    func confirm(_ suggestion: RecurrenceSuggestion, autoRecord: Bool, repo: any ITransactionRepository) async -> Bool {
        withAnimation { suggestions.removeAll { $0.id == suggestion.id } }
        do {
            try await repo.addRecurrenceRule(suggestion.ruleInput(autoRecord: autoRecord))
            answeredCount += 1
            return true
        } catch {
            withAnimation { suggestions.insert(suggestion, at: 0) }
            errorMessage = String(localized: "Couldn't save \(suggestion.title). Please try again.")
            return false
        }
    }

    /// "Still paying": the payment is skipped, not the commitment — asks again only if the next one is missed too.
    func stillPaying(_ payment: MissedPayment, repo: any ITransactionRepository) async -> Bool {
        withAnimation { missed.removeAll { $0.id == payment.id } }
        do {
            try await repo.advanceRecurrenceRule(id: payment.rule.id, cursor: payment.due, amount: nil)
            answeredCount += 1
            return true
        } catch {
            withAnimation { missed.insert(payment, at: 0) }
            errorMessage = String(localized: "Couldn't save \(payment.title). Please try again.")
            return false
        }
    }

    /// "Not fixed": remembered for good once the undo toast expires.
    func dismiss(_ suggestion: RecurrenceSuggestion) -> PendingUndo {
        withAnimation { suggestions.removeAll { $0.id == suggestion.id } }
        pendingSuggestionPattern = RecurrenceDetector.dismissalPattern(for: suggestion)
        return PendingUndo(
            message: String(localized: "Won't suggest \(suggestion.title) again"),
            suggestionId: suggestion.id,
            ruleId: nil,
            commit: { DismissedRecurrencePatterns.dismiss([suggestion]) },
            restore: { [weak self] in withAnimation { self?.suggestions.insert(suggestion, at: 0) } }
        )
    }

    /// "Stopped paying": ends the rule once the undo toast expires, so it stops being planned for.
    func stopped(_ payment: MissedPayment, repo: any ITransactionRepository) -> PendingUndo {
        withAnimation { missed.removeAll { $0.id == payment.id } }
        return PendingUndo(
            message: String(localized: "Stopped planning for \(payment.title)"),
            suggestionId: nil,
            ruleId: payment.rule.id,
            commit: { try? await repo.closeRecurrenceRule(id: payment.rule.id, endDate: .now) },
            restore: { [weak self] in withAnimation { self?.missed.insert(payment, at: 0) } }
        )
    }

    // MARK: Undo

    /// Shows `undo`, first writing any answer still waiting so two never overlap.
    func offer(_ undo: PendingUndo) async {
        await commitPending()
        // Let the card's removal animation finish first, so the two motions don't overlap.
        try? await Task.sleep(for: .milliseconds(350))
        pendingUndo = undo
    }

    func commitPending() async {
        guard let undo = pendingUndo else { return }
        pendingUndo = nil
        pendingSuggestionPattern = nil
        await undo.commit()
        answeredCount += 1
    }

    func undoPending() {
        guard let undo = pendingUndo else { return }
        pendingUndo = nil
        pendingSuggestionPattern = nil
        undo.restore()
    }
}

/// Plan's "Fixed expenses to confirm" section. The host owns `model` and reloads it from its
/// own `.task(id: dataChanged.revision)`, and only shows this when `!model.isEmpty`: a task on a
/// zero-size view inside a lazy stack didn't re-run on data changes, so new suggestions only
/// showed up after a relaunch. The host also applies `.fixedExpenseFeedback(model)`, which must
/// outlive this section (it disappears with its last card, the undo toast must not).
struct FixedExpensesSection: View {
    let model: CommittedSpendingModel
    @Environment(TransactionListViewModel.self) private var transactionListViewModel
    @Environment(DataChangedSignal.self) private var dataChanged

    private var repo: any ITransactionRepository { transactionListViewModel.repo }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fixed expenses to confirm")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                // Said once here rather than on every card.
                Text("Planning for them adds them to Coming up. We won't add transactions without your permission.")
                    .font(.caption)
                    .foregroundStyle(.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.missed) { payment in
                MissedPaymentCard(
                    payment: payment,
                    onStillPaying: { write { await model.stillPaying(payment, repo: repo) } },
                    onStopped: { Task { await model.offer(model.stopped(payment, repo: repo)) } }
                )
            }
            ForEach(model.suggestions) { suggestion in
                FixedExpenseSuggestionCard(
                    suggestion: suggestion,
                    onConfirm: { autoRecord in write { await model.confirm(suggestion, autoRecord: autoRecord, repo: repo) } },
                    onDismiss: { Task { await model.offer(model.dismiss(suggestion)) } }
                )
            }
        }
        .tint(.accentIndigo)
        .controlSize(.large)
    }

    /// Bumps the shared signal after a successful write so Coming up / Safe Spend re-read the rules.
    private func write(_ work: @escaping () async -> Bool) {
        Task { if await work() { dataChanged.bump() } }
    }
}

extension View {
    /// Undo toast, error alert and success haptic for `FixedExpensesSection`'s answers.
    func fixedExpenseFeedback(_ model: CommittedSpendingModel) -> some View {
        modifier(FixedExpenseFeedback(model: model))
    }
}

private struct FixedExpenseFeedback: ViewModifier {
    @Bindable var model: CommittedSpendingModel
    @Environment(DataChangedSignal.self) private var dataChanged

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let undo = model.pendingUndo {
                    ToastBanner(icon: "checkmark.circle.fill", message: undo.message) {
                        Button("Undo") { model.undoPending() }
                            .font(.subheadline.bold())
                            .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)   // the tab content already ends above the tab bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: undo.id) {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled, model.pendingUndo?.id == undo.id else { return }
                        await model.commitPending()
                        dataChanged.bump()
                    }
                }
            }
            .animation(.spring(duration: 0.3), value: model.pendingUndo?.id)
            .sensoryFeedback(.success, trigger: model.answeredCount)
            .alert(
                "Couldn't save",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
    }
}

private struct FixedExpenseSuggestionCard: View {
    let suggestion: RecurrenceSuggestion
    let onConfirm: (_ autoRecord: Bool) -> Void
    let onDismiss: () -> Void

    @State private var autoRecord = false

    /// "≈" when the amounts varied: the median is a forecast, not the bill.
    private var amountText: String {
        suggestion.amountsIdentical
            ? suggestion.amount.formattedEUR()
            : String(localized: "≈ \(suggestion.amount.formattedEUR())")
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: CategoryInfo.info(for: suggestion.category).symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CategoryInfo.info(for: suggestion.category).color)
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.body)
                            .foregroundStyle(.textPrimary)
                            .lineLimit(2)
                        Text("\(suggestion.frequency.cadenceLabel(interval: suggestion.interval)) · \(suggestion.occurrenceCount) payments")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                    }
                    Spacer()
                    Text(amountText)
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                        .privacyBlur()
                }
                .accessibilityElement(children: .combine)

                if suggestion.amountsIdentical {
                    Toggle("Record it for me each time", isOn: $autoRecord)
                        .font(.subheadline)
                        .tint(.accentIndigo)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { actions }
                    VStack(spacing: 8) { actions }
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        Button(action: onDismiss) { Text("Not fixed").frame(maxWidth: .infinity) }
            .buttonStyle(.bordered)
            .accessibilityHint("Won't suggest this payment again")
        Button { onConfirm(autoRecord) } label: { Text("Plan for it").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Adds it to Coming up")
    }
}

private struct MissedPaymentCard: View {
    let payment: MissedPayment
    let onStillPaying: () -> Void
    let onStopped: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Do you still pay \(payment.title)?")
                        .font(.body.bold())
                        .foregroundStyle(.textPrimary)
                    Text("No payment found around \(payment.due.formatted(.dateTime.day().month(.abbreviated))).")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
                .accessibilityElement(children: .combine)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { actions }
                    VStack(spacing: 8) { actions }
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        Button(action: onStopped) { Text("Stopped paying").frame(maxWidth: .infinity) }
            .buttonStyle(.bordered)
            .accessibilityHint("Stops planning for this payment")
        Button(action: onStillPaying) { Text("Still paying").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Skips this payment and keeps planning the next ones")
    }
}
