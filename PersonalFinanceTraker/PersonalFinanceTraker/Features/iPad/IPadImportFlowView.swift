//
//  IPadImportFlowView.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// The iPad CSV import: mapping controls on the left, a live preview of the result on the right.
///
/// iPhone keeps the three-step wizard (`ImportFlowView`) because a phone can only show one decision
/// at a time. On iPad that sequencing is the problem, not the solution — you make mapping choices on
/// one screen and only learn what they did to your data two screens later. Here the preview is
/// always the same pane, always showing mapped output, so the third step stops existing: the
/// confirmation *is* what you have been looking at the whole time. Detected recurrences get a tab
/// of their own rather than iPhone's post-import screen, for the same reason: review before, not after.
struct IPadImportFlowView: View {
    @Bindable var viewModel: TransactionListViewModel

    private enum Step: Hashable {
        case columns
        case categories
        case recurring
    }

    @State private var step: Step = .columns

    /// Re-mapping is keyed off this rather than off each field: `.task(id:)` cancels the in-flight
    /// run whenever it changes, which is the debounce — no timer, no cancellation bookkeeping.
    private var mappingSignature: String {
        let m = viewModel.columnMapping
        let selections = viewModel.categoryResolutionSelections
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return [
            m.dateColumn ?? "", m.amountColumn ?? "", m.typeColumn ?? "",
            m.categoryColumn ?? "", m.noteColumn ?? "", m.currencyColumn ?? "",
            m.dateFormat, "\(m.signConvention)", selections
        ].joined(separator: "|")
    }

    private var hasCategoryStep: Bool { viewModel.columnMapping.categoryColumn != nil }
    private var hasRecurringStep: Bool { !viewModel.recurrenceSuggestions.isEmpty }

    var body: some View {
        // One NavigationStack for the whole sheet, not one per pane. A pane's own stack measures
        // its bar's margins from the pane, whose outer edge is the sheet's rounded corner — which
        // is how Cancel and the checkmark ended up sitting on the curve. The sheet's root bar gets
        // margins that account for the presentation inset, the same as every other sheet here.
        NavigationStack {
            HStack(spacing: 0) {
                controls
                    // Ranged, not fixed: a hard width plus a squeezed sibling is how the preview
                    // ended up ~180pt wide and wrapping one character per line.
                    .frame(minWidth: 360, idealWidth: 460, maxWidth: 520)
                Divider()
                preview
                    .frame(minWidth: 420)
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancelImport() }
                }
            }
        }
        .background { AppBackground() }
        // Without this the sheet is form-width, and two panes don't fit in a form.
        .presentationSizing(.page)
        // Cancel is the only way out: a stray downward swipe over a form field would otherwise throw
        // away a column mapping and 15 category decisions with no confirmation and no undo.
        .interactiveDismissDisabled()
        .presentationBackground { AppBackground() }
        .task(id: mappingSignature) {
            await remap()
        }
        // Remapping can wipe the suggestions out from under a selected Recurring tab.
        .onChange(of: hasRecurringStep) { _, stillThere in
            if !stillThere && step == .recurring { step = .columns }
        }
    }

    // MARK: - Left: the mapping controls

    private var controls: some View {
        // A VStack, not a .safeAreaInset overlay: an inset floats above the scroll view, so the
        // list still travels underneath it and needs a background to hide behind. Giving the
        // picker its own row in the layout means there is nothing to hide.
        VStack(spacing: 0) {
            stepPicker
            stepContent
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        Group {
                switch step {
                case .columns:
                    if let file = viewModel.csvFile {
                        CSVColumnMappingView(
                            file: file,
                            mapping: $viewModel.columnMapping,
                            currentStep: 1,
                            totalSteps: 1,
                            onContinue: {},
                            onCancel: { viewModel.cancelImport() },
                            showsStepActions: false
                        )
                    }
                case .categories:
                    CSVCategoryMappingView(
                        csvCategories: viewModel.csvCategories,
                        categoryTypes: viewModel.csvCategoryTypes,
                        availableCategories: viewModel.availableCategories,
                        selections: $viewModel.categoryResolutionSelections,
                        currentStep: 2,
                        totalSteps: 2,
                        onContinue: {},
                        showsStepActions: false
                    )
                case .recurring:
                    RecurrenceSuggestionsView(viewModel: viewModel, mode: .preview)
                }
        }
    }

    @ViewBuilder
    private var stepPicker: some View {
        // Only offered when there is a second decision to make — otherwise a lone tab leads nowhere.
        if hasCategoryStep || hasRecurringStep {
            Picker("Step", selection: $step) {
                Text("Columns").tag(Step.columns)
                if hasCategoryStep {
                    Text("Categories").tag(Step.categories)
                }
                if hasRecurringStep {
                    Text("Recurring").tag(Step.recurring)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Right: the live result

    /// No NavigationStack of its own — its confirm action rises into the sheet's single bar.
    private var preview: some View {
        ImportResultView(
            rows: viewModel.mappedRows,
            availableCategories: viewModel.availableCategories,
            isImporting: viewModel.isImporting,
            // 0 suppresses the "Step n of m" subtitle: this pane is not a step here.
            currentStep: 0,
            totalSteps: 0,
            // Confirming here also writes whatever is still checked under Recurring. Not
            // visiting that tab means accepting all of it, which is the pre-checked default.
            onConfirm: { viewModel.confirmImport($0, addingRecurrenceRules: true) },
            onDone: { viewModel.cancelImport() }
        )
    }

    // MARK: - Live mapping

    /// Recomputes the preview from the current mapping. Category extraction has to happen here too,
    /// because on iPhone it was tied to leaving step 1 — an event this layout doesn't have.
    private func remap() async {
        guard let file = viewModel.csvFile else { return }
        // Long enough that typing a date format doesn't remap on every keystroke; the `.task(id:)`
        // cancellation means an abandoned run costs nothing.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        if hasCategoryStep {
            let mapping = viewModel.columnMapping
            let (categories, types) = await Task.detached(priority: .userInitiated) {
                CSVColumnMapper.extractCategoriesAndTypes(from: file, mapping: mapping)
            }.value
            guard !Task.isCancelled else { return }
            viewModel.csvCategories = categories
            viewModel.csvCategoryTypes = types
            viewModel.applySavedCategorySelections()
            // Auto-map here rather than waiting for the category tab to appear: the preview is
            // showing these rows now, and unresolved ones would all read as new categories.
            // resolve() never overwrites an existing choice, so re-running it is harmless.
            viewModel.categoryResolutionSelections = CategoryAutoMapper.resolve(
                csvCategories: categories,
                categoryTypes: types,
                availableCategories: viewModel.availableCategories,
                existing: viewModel.categoryResolutionSelections
            )
            viewModel.hasAutoMappedCategories = true
        } else {
            viewModel.categoryResolutionSelections = [:]
            viewModel.csvCategories = []
            viewModel.csvCategoryTypes = [:]
        }

        guard !Task.isCancelled else { return }
        await viewModel.applyMapping()
    }
}
