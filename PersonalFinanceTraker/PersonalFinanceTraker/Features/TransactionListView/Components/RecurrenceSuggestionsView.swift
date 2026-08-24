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
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(headerTitle)
                        .font(.title3.bold())
                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .appFormSectionBackground()

            if !viewModel.recurrenceSuggestions.isEmpty {
                Section {
                    ForEach(viewModel.recurrenceSuggestions) { suggestion in
                        suggestionRow(suggestion)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation {
                                    toggleSelection(suggestion.id)
                                }
                            }
                            .accessibilityElement()
                            .accessibilityLabel(accessibilityLabel(for: suggestion))
                            .accessibilityAddTraits(
                                viewModel.selectedSuggestionIds.contains(suggestion.id)
                                    ? .isSelected
                                    : []
                            )
                    }
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
                        Button {
                            Task {
                                isProcessing = true
                                await viewModel.addSelectedRecurrenceRules()
                                isProcessing = false
                            }
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel(String(localized: "Add Rules"))
                        .disabled(viewModel.selectedSuggestionIds.isEmpty)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        viewModel.cancelImport()
                    } label: {
                        Text(String(localized: "Skip"))
                    }
                }
            }
        }
    }

    private var headerTitle: String {
        switch mode {
        case .wizardStep:
            let count = viewModel.importedTransactionCount
            return count == 1
                ? String(localized: "Imported \(count) transaction")
                : String(localized: "Imported \(count) transactions")
        case .preview:
            let count = viewModel.recurrenceSuggestions.count
            return count == 1
                ? String(localized: "\(count) recurring transaction found")
                : String(localized: "\(count) recurring transactions found")
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .wizardStep:
            return String(localized: "These look like repeating transactions. Add recurrence rules to track them automatically.")
        case .preview:
            return String(localized: "Checked ones become recurrence rules when you import. Uncheck anything you don't want tracked.")
        }
    }

    private func suggestionRow(_ suggestion: RecurrenceSuggestion) -> some View {
        let isSelected = viewModel.selectedSuggestionIds.contains(suggestion.id)
        let mapped = suggestion.categoryPersistentId.flatMap { categoryByPersistentId[$0] }
        let symbol = mapped?.systemImage ?? CategoryInfo.info(for: suggestion.category).symbol
        let tint = mapped.map { Color(categoryToken: $0.colorToken) }
            ?? CategoryInfo.info(for: suggestion.category).color

        return HStack(spacing: 12) {
            // Selection checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? .accentIndigo : .secondary)
                .frame(width: 24, height: 24)

            // Category icon
            GlassCard(tint: tint.opacity(0.12), borderRadius: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16, height: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.note)
                    .font(.subheadline)
                Text(cadenceLabel(for: suggestion) + " · " + String(localized: "starts \(suggestion.nextDate.formatted(date: .abbreviated, time: .omitted))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Seen \(suggestion.occurrenceCount) times"))
                    .font(.caption2)
                    .foregroundStyle(.textDim)
            }

            Spacer()

            Text(formattedSignedAmount(suggestion.amount, currencyCode: suggestion.currencyCode))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(suggestion.amount >= 0 ? .positive : .negative)
                .privacyBlur()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func cadenceLabel(for suggestion: RecurrenceSuggestion) -> String {
        suggestion.interval == 1
            ? suggestion.frequency.label
            : String(localized: "Every \(suggestion.interval) \(suggestion.frequency.unitLabel(for: suggestion.interval))")
    }

    private func formattedSignedAmount(_ amount: Decimal, currencyCode: String) -> String {
        let magnitude = amount.formattedEUR(currency: currencyCode)
        return amount >= 0 ? "+\(magnitude)" : magnitude
    }

    private func toggleSelection(_ id: UUID) {
        if viewModel.selectedSuggestionIds.contains(id) {
            viewModel.selectedSuggestionIds.remove(id)
        } else {
            viewModel.selectedSuggestionIds.insert(id)
        }
    }

    private func accessibilityLabel(for suggestion: RecurrenceSuggestion) -> String {
        let amount = formattedSignedAmount(suggestion.amount, currencyCode: suggestion.currencyCode)
        let date = suggestion.nextDate.formatted(date: .abbreviated, time: .omitted)
        return "\(suggestion.note), \(cadenceLabel(for: suggestion)), \(amount), starts \(date), seen \(suggestion.occurrenceCount) times"
    }
}
