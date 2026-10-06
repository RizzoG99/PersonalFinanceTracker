//
//  RecurrenceSuggestionsView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct RecurrenceSuggestionsView: View {
    /// iPhone reaches this list as the last wizard step, *after* the rows are saved, so it owns the
    /// confirm/skip actions. iPad shows the same list as a third segment *before* the import runs —
    /// there the checkboxes are the whole interaction and the import button lives in the other pane.
    enum Mode: Equatable {
        case wizardStep(current: Int, total: Int)
        case preview
    }

    @Bindable var viewModel: TransactionListViewModel
    let mode: Mode
    @State private var isProcessing = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 16

    private var categoryByPersistentId: [PersistentIdentifier: CategorySnapshot] {
        Dictionary(uniqueKeysWithValues: viewModel.availableCategories.map { ($0.persistentId, $0) })
    }

    private var isWizardStep: Bool {
        if case .wizardStep = mode { return true }
        return false
    }

    /// See ImportResultView.barTitle — as the iPad sheet's Recurring pane this shares one bar with
    /// the preview pane, so both siblings have to name it the same thing.
    private var barTitle: LocalizedStringKey {
        isWizardStep ? "Recurring Transactions" : "Import"
    }

    private var stepSubtitle: String {
        guard case let .wizardStep(current, total) = mode else { return "" }
        return "Step \(current) of \(total)"
    }

    var body: some View {
        List {
            if isWizardStep {
                Section {
                    Text(String(localized: "Imported \(viewModel.importedTransactionCount) transactions."))
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .appFormSectionBackground()
            }

            if !viewModel.recurrenceSuggestions.isEmpty {
                Section {
                    ForEach(viewModel.recurrenceSuggestions) { suggestion in
                        Button {
                            withAnimation { viewModel.toggleSuggestion(suggestion.id) }
                        } label: {
                            suggestionRow(suggestion)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityLabel(for: suggestion))
                        .accessibilityHint(String(localized: "Checked ones are planned for in Coming up"))
                        .accessibilityAddTraits(
                            viewModel.selectedSuggestionIds.contains(suggestion.id) ? .isSelected : []
                        )
                    }
                } header: {
                    // Next to the rows rather than at the top, so it doesn't scroll away from them.
                    VStack(alignment: .leading, spacing: 8) {
                        Text(headerTitle)
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                        Text("Checked ones go to Coming up — we won't add transactions without your permission. Ones you uncheck won't be suggested again.")
                            .font(.footnote)
                            .foregroundStyle(.textMid)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(allSelected ? "Deselect all" : "Select all") {
                            withAnimation { viewModel.setAllSuggestions(selected: !allSelected) }
                        }
                        .font(.subheadline.bold())
                        .tint(.accentIndigo)
                        .frame(minHeight: 44)
                    }
                    .textCase(nil)
                }
                .appFormSectionBackground()
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(barTitle)
        .navigationSubtitle(stepSubtitle)
        .navigationBarTitleDisplayMode(.inline)
        // The rows are already saved by the time this step appears, so Back would return to a
        // preview claiming 1634 rows are new and re-confirming would end the wizard on "Skipped
        // 1634 duplicates", losing these suggestions. Skip is the way out instead.
        .navigationBarBackButtonHidden(isWizardStep)
        .toolbar {
            if case .wizardStep = mode {
                ToolbarItem(placement: .confirmationAction) {
                    if isProcessing {
                        ProgressView()
                    } else {
                        // Always enabled: with nothing checked it still records what was unchecked.
                        Button(confirmTitle) {
                            Task {
                                isProcessing = true
                                await viewModel.addSelectedRecurrenceRules()
                                isProcessing = false
                            }
                        }
                        .bold()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    // Decide later: nothing is planned and nothing is remembered as "Not fixed".
                    Button(String(localized: "Skip")) {
                        viewModel.cancelImport()
                    }
                }
            }
        }
    }

    private var selectedCount: Int { viewModel.selectedSuggestionIds.count }

    private var allSelected: Bool { selectedCount == viewModel.recurrenceSuggestions.count }

    private var confirmTitle: String {
        selectedCount == 0 ? String(localized: "Done") : String(localized: "Plan \(selectedCount)")
    }

    private var headerTitle: String {
        String(localized: "\(viewModel.recurrenceSuggestions.count) recurring transactions found")
    }

    private func suggestionRow(_ suggestion: RecurrenceSuggestion) -> some View {
        let isSelected = viewModel.selectedSuggestionIds.contains(suggestion.id)
        let mapped = suggestion.categoryPersistentId.flatMap { categoryByPersistentId[$0] }
        let symbol = mapped?.systemImage ?? CategoryInfo.info(for: suggestion.category).symbol
        let tint = mapped.map { Color(categoryToken: $0.colorToken) }
            ?? CategoryInfo.info(for: suggestion.category).color

        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isSelected ? .accentIndigo : .secondary)
                .frame(minWidth: 28)

            if !dynamicTypeSize.isAccessibilitySize {
                GlassCard(tint: tint.opacity(0.12), borderRadius: 12) {
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: iconSize, height: iconSize)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.subheadline)
                    .foregroundStyle(.textPrimary)
                Text("\(cadenceLabel(for: suggestion)) · \(suggestion.occurrenceCount) payments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Next \(nextDateText(suggestion.nextDate))"))
                    .font(.caption)
                    .foregroundStyle(.textDim)
                // At accessibility sizes the amount drops under the text instead of squeezing it.
                if dynamicTypeSize.isAccessibilitySize {
                    amountText(suggestion)
                }
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
                amountText(suggestion)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Every row is an expense, so no red: "≈" marks a variable bill's typical amount, as in Plan.
    private func amountText(_ suggestion: RecurrenceSuggestion) -> some View {
        Text(amountString(suggestion))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.textPrimary)
            .privacyBlur()
    }

    private func amountString(_ suggestion: RecurrenceSuggestion) -> String {
        let amount = suggestion.amount.formattedEUR(currency: suggestion.currencyCode)
        return suggestion.amountsIdentical ? amount : String(localized: "≈ \(amount)")
    }

    /// "10 Nov" — the year only when it isn't this year's.
    private func nextDateText(_ date: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return sameYear
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func cadenceLabel(for suggestion: RecurrenceSuggestion) -> String {
        suggestion.frequency.cadenceLabel(interval: suggestion.interval)
    }

    private func accessibilityLabel(for suggestion: RecurrenceSuggestion) -> String {
        let amount = suggestion.amountsIdentical
            ? suggestion.amount.formattedEUR(currency: suggestion.currencyCode)
            : String(localized: "about \(suggestion.amount.formattedEUR(currency: suggestion.currencyCode))")
        return String(localized: "\(suggestion.title), \(cadenceLabel(for: suggestion)), \(amount), \(suggestion.occurrenceCount) payments, next \(nextDateText(suggestion.nextDate))")
    }
}
