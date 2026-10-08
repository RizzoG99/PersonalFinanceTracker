//
//  FixedExpensesSection.swift
//  PersonalFinanceTraker
//

import SwiftUI

extension RecurrenceRuleSnapshot {
    /// The name, or the category when there is none — a goal transfer's "→ Goal" shows as the goal.
    var title: String {
        note.isEmpty ? category.removingLeadingEmoji.localizedCategoryDisplay : note
    }
}

/// A forecast-only rule whose payment never arrived (#188).
struct MissedPayment: Identifiable {
    var id: UUID { rule.id }
    let rule: RecurrenceRuleSnapshot
    let due: Date

    var title: String { rule.title }

    /// "I paid it" (#206): the add form, pre-filled so that saving it matches the rule
    /// (`RecurrenceDetector.paidThrough`: same note or goal, amount, due date) and moves its cursor.
    var draft: TransactionDraft {
        TransactionDraft(
            amount: Double(truncating: abs(rule.amount) as NSDecimalNumber),
            transactionType: rule.goalId == nil ? .expense : .transfer,
            categoryName: rule.category,
            note: rule.note,
            currencyCode: rule.currencyCode,
            date: due,
            goalId: rule.goalId
        )
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
    /// Every card waiting for an answer — Home's "N fixed expenses to check" row (#206).
    var count: Int { missed.count + suggestions.count }
    /// The "Review N more" sheet is up: answers' feedback shows there instead of on the host.
    var reviewingAll = false
    /// The missed payment whose pre-filled "I paid it" form is open.
    var paying: MissedPayment?

    /// Cards shown inline before "Review N more" (#206): a first detection on a long history
    /// would otherwise push Coming up off screen.
    nonisolated static let inlineLimit = 2

    /// How many missed / suggestion cards fit in `limit` — missed first, they're overdue.
    nonisolated static func inlineCounts(missed: Int, suggestions: Int, limit: Int = inlineLimit) -> (missed: Int, suggestions: Int) {
        let shownMissed = min(missed, limit)
        return (shownMissed, min(suggestions, limit - shownMissed))
    }

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

    /// "Skip this one": the payment is skipped, not the commitment — asks again only if the next one is missed too.
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

/// Plan's "Check your fixed expenses" section. The host owns `model` and reloads it from its
/// own `.task(id: dataChanged.revision)`, and only shows this when `!model.isEmpty`: a task on a
/// zero-size view inside a lazy stack didn't re-run on data changes, so new suggestions only
/// showed up after a relaunch. The host also applies `.fixedExpenseFeedback(model)`, which must
/// outlive this section (it disappears with its last card, the undo toast must not).
struct FixedExpensesSection: View {
    let model: CommittedSpendingModel
    /// The "Review N more" sheet: every card, no header (the sheet's title says it).
    var showsAll = false
    @Environment(TransactionListViewModel.self) private var transactionListViewModel
    @Environment(DataChangedSignal.self) private var dataChanged

    private var repo: any ITransactionRepository { transactionListViewModel.repo }

    var body: some View {
        let shown = showsAll
            ? (missed: model.missed.count, suggestions: model.suggestions.count)
            : CommittedSpendingModel.inlineCounts(missed: model.missed.count, suggestions: model.suggestions.count)
        let more = model.count - shown.missed - shown.suggestions
        VStack(alignment: .leading, spacing: 12) {
            if !showsAll {
                // The subtitle is said once here rather than on every card.
                PlanSectionHeader(
                    "Check your fixed expenses",
                    subtitle: "Planning for them adds them to Coming up. We won't add transactions without your permission."
                )
            }
            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 12) {
                    ForEach(model.missed.prefix(shown.missed)) { payment in
                        MissedPaymentCard(
                            payment: payment,
                            compact: shown.missed > 1,
                            onPaid: { model.paying = payment },
                            onSkip: { write { await model.stillPaying(payment, repo: repo) } },
                            onStopped: { Task { await model.offer(model.stopped(payment, repo: repo)) } }
                        )
                    }
                    ForEach(model.suggestions.prefix(shown.suggestions)) { suggestion in
                        FixedExpenseSuggestionCard(
                            suggestion: suggestion,
                            onConfirm: { autoRecord in write { await model.confirm(suggestion, autoRecord: autoRecord, repo: repo) } },
                            onDismiss: { Task { await model.offer(model.dismiss(suggestion)) } }
                        )
                    }
                }
            }
            if more > 0 {
                // Same shape as Home's "N fixed expenses to check" row.
                Button { model.reviewingAll = true } label: {
                    HStack {
                        Text("Review \(more) more")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.accentIndigo)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .tint(.accentIndigo)
        // One size whatever the count (switching when a card leaves made the rest jump), and
        // large so every button reaches the 44pt target.
        .controlSize(.large)
    }

    /// Bumps the shared signal after a successful write so Coming up / Safe Spend re-read the rules.
    private func write(_ work: @escaping () async -> Bool) {
        Task { if await work() { dataChanged.bump() } }
    }
}

extension View {
    /// Undo toast, error alert, success haptic, the "I paid it" form and the "Review N more"
    /// sheet for `FixedExpensesSection`'s answers.
    func fixedExpenseFeedback(_ model: CommittedSpendingModel, materializationService: RecurrenceMaterializationService) -> some View {
        modifier(FixedExpenseFeedback(model: model, materializationService: materializationService, inReviewSheet: false))
    }
}

/// Applied twice: on the host, and inside the "Review N more" sheet. Only the one on top is
/// active — a toast or alert on the host would sit hidden under the sheet.
private struct FixedExpenseFeedback: ViewModifier {
    @Bindable var model: CommittedSpendingModel
    let materializationService: RecurrenceMaterializationService
    let inReviewSheet: Bool
    @Environment(TransactionListViewModel.self) private var transactionListViewModel
    @Environment(DataChangedSignal.self) private var dataChanged

    private var isActive: Bool { model.reviewingAll == inReviewSheet }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isActive, let undo = model.pendingUndo {
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
            .sensoryFeedback(.success, trigger: model.answeredCount) { _, _ in isActive }
            .alert(
                "Couldn't save",
                isPresented: Binding(
                    get: { isActive && model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            // Saving bumps the data signal; the reload matches the payment and the card goes.
            .sheet(item: Binding(get: { isActive ? model.paying : nil }, set: { model.paying = $0 })) { payment in
                NavigationStack {
                    EditAddTransactionView(draft: payment.draft, repo: transactionListViewModel.repo, materializationService: materializationService)
                }
                .presentationBackground { AppBackground() }
            }
            .modifier(ReviewAllSheet(model: model, materializationService: materializationService, isHost: !inReviewSheet))
    }
}

/// "Review N more": every card in a sheet, presented by the host so it survives the section.
private struct ReviewAllSheet: ViewModifier {
    @Bindable var model: CommittedSpendingModel
    let materializationService: RecurrenceMaterializationService
    let isHost: Bool

    func body(content: Content) -> some View {
        if isHost {
            content
                .sheet(isPresented: $model.reviewingAll) {
                    NavigationStack {
                        ScrollView {
                            FixedExpensesSection(model: model, showsAll: true)
                                .padding(16)
                                .readableWidth()
                        }
                        .navigationTitle("Check your fixed expenses")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { model.reviewingAll = false }
                            }
                        }
                        .modifier(FixedExpenseFeedback(model: model, materializationService: materializationService, inReviewSheet: true))
                    }
                    .presentationBackground { AppBackground() }
                }
                // Last card answered: nothing left to review.
                .onChange(of: model.isEmpty) { _, isEmpty in
                    if isEmpty { model.reviewingAll = false }
                }
        } else {
            content
        }
    }
}

private struct FixedExpenseSuggestionCard: View {
    let suggestion: RecurrenceSuggestion
    let onConfirm: (_ autoRecord: Bool) -> Void
    let onDismiss: () -> Void

    @State private var autoRecord = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                // "seen N times", not "N payments": a count of payments read as N still due.
                // "≈" when the amounts varied: the median is a forecast, not the bill.
                ChargeRowLayout(
                    category: suggestion.category, title: Text(suggestion.title),
                    amount: suggestion.amount, currencyCode: suggestion.currencyCode,
                    approximate: !suggestion.amountsIdentical
                ) {
                    Text("\(suggestion.frequency.cadenceLabel(interval: suggestion.interval)) · seen \(suggestion.occurrenceCount) times")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
                .accessibilityElement(children: .combine)

                if suggestion.offersAutoRecord {
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
            .secondaryCardButton()
            .accessibilityHint("Won't suggest this payment again")
        Button { onConfirm(autoRecord) } label: { Text("Plan for it").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Adds it to Coming up")
    }
}

private struct MissedPaymentCard: View {
    let payment: MissedPayment
    /// Several missed cards at once: the two plan-changing answers fold into a ⋯ menu, so
    /// each card shows one button instead of three.
    let compact: Bool
    let onPaid: () -> Void
    let onSkip: () -> Void
    let onStopped: () -> Void

    /// A goal transfer is saving, not paying (#209). Typed `LocalizedStringKey` so the
    /// ternaries below stay catalog keys rather than plain Strings.
    private var isGoal: Bool { payment.rule.goalId != nil }
    private var question: LocalizedStringKey {
        isGoal ? "Still saving for \(payment.title)?" : "Do you still pay \(payment.title)?"
    }
    private var notFound: LocalizedStringKey {
        let due = payment.due.formatted(.dateTime.day().month(.abbreviated))
        return isGoal ? "No transfer found around \(due)." : "No payment found around \(due)."
    }
    private var paidLabel: LocalizedStringKey { isGoal ? "I saved it" : "I paid it" }
    private var paidHint: LocalizedStringKey {
        isGoal ? "Opens the transfer, ready to save" : "Opens the payment, ready to save"
    }
    private var stoppedLabel: LocalizedStringKey { isGoal ? "Stopped saving" : "Stopped paying" }
    private var stoppedHint: LocalizedStringKey {
        isGoal ? "Stops planning for this transfer" : "Stops planning for this payment"
    }
    private var skipHint: LocalizedStringKey {
        isGoal ? "Skips this transfer and keeps planning the next ones" : "Skips this payment and keeps planning the next ones"
    }

    var body: some View {
        let rule = payment.rule
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                ChargeRowLayout(category: rule.category, title: Text(question), amount: rule.amount, currencyCode: rule.currencyCode) {
                    Text(notFound)
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
                .accessibilityElement(children: .combine)

                if compact {
                    HStack(spacing: 12) {
                        paidButton
                        Menu {
                            Button(action: onSkip) { Label("Skip this one", systemImage: "forward") }
                                .accessibilityHint(skipHint)
                            Button(action: onStopped) { Label(stoppedLabel, systemImage: "xmark.circle") }
                                .accessibilityHint(stoppedHint)
                        } label: {
                            // Circle at the control size's height: a 44pt frame inside the
                            // bordered padding drew it twice as tall as "I paid it".
                            Image(systemName: "ellipsis")
                                .accessibilityLabel(Text("More answers for \(payment.title)"))
                        }
                        .secondaryCardButton()
                        .buttonBorderShape(.circle)
                    }
                } else {
                    // Recording it is the likely answer; the two that change the plan sit under it.
                    paidButton
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { secondaryActions }
                        VStack(spacing: 8) { secondaryActions }
                    }
                }
            }
        }
    }

    private var paidButton: some View {
        Button(action: onPaid) { Text(paidLabel).frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent)
            .accessibilityHint(paidHint)
    }

    @ViewBuilder private var secondaryActions: some View {
        Button(action: onSkip) { Text("Skip this one").frame(maxWidth: .infinity) }
            .secondaryCardButton()
            .accessibilityHint(skipHint)
        Button(action: onStopped) { Text(stoppedLabel).frame(maxWidth: .infinity) }
            .secondaryCardButton()
            .accessibilityHint(stoppedHint)
    }
}

private extension View {
    /// Neutral grey, not the indigo tint: on the dark glass card an indigo fill all but vanished
    /// (and its indigo label fell under 4.5:1). Also sets it apart from the prominent answer.
    func secondaryCardButton() -> some View {
        buttonStyle(.bordered).tint(.primary)
    }
}
