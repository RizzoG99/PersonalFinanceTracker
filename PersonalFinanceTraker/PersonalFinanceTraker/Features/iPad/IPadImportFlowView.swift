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
/// confirmation *is* what you have been looking at the whole time.
struct IPadImportFlowView: View {
    @Bindable var viewModel: TransactionListViewModel

    private enum Step: Hashable {
        case columns
        case categories
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

    var body: some View {
        HStack(spacing: 0) {
            controls
                // Ranged, not fixed: a hard width plus a squeezed sibling is how the preview ended
                // up ~180pt wide and wrapping one character per line.
                .frame(minWidth: 360, idealWidth: 460, maxWidth: 520)
            Divider()
            preview
                .frame(minWidth: 420)
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
    }

    // MARK: - Left: the mapping controls

    private var controls: some View {
        NavigationStack {
            // A VStack, not a .safeAreaInset overlay: an inset floats above the scroll view, so the
            // list still travels underneath it and needs a background to hide behind. Giving the
            // picker its own row in the layout means there is nothing to hide.
            VStack(spacing: 0) {
                stepPicker
                stepContent
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { viewModel.cancelImport() }
                }
            }
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
                }
        }
    }

    @ViewBuilder
    private var stepPicker: some View {
        // Only offered when the file actually has a category column — otherwise there is nothing
        // to map and a second tab would lead to an empty screen.
        if hasCategoryStep {
            Picker("Step", selection: $step) {
                Text("Columns").tag(Step.columns)
                Text("Categories").tag(Step.categories)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Right: the live result

    private var preview: some View {
        NavigationStack {
            ImportResultView(
                rows: viewModel.mappedRows,
                availableCategories: viewModel.availableCategories,
                isImporting: viewModel.isImporting,
                // 0 suppresses the "Step n of m" subtitle: this pane is not a step here.
                currentStep: 0,
                totalSteps: 0,
                onConfirm: { viewModel.confirmImport($0) },
                onDone: { viewModel.cancelImport() }
            )
        }
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
