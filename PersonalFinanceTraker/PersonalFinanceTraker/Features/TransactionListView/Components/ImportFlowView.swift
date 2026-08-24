//
//  ImportFlowView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct ImportFlowView: View {
    @Bindable var viewModel: TransactionListViewModel

    private var importSteps: Int {
        viewModel.columnMapping.categoryColumn != nil ? 3 : 2
    }

    private var totalSteps: Int {
        importSteps + (viewModel.recurrenceSuggestions.isEmpty ? 0 : 1)
    }

    var body: some View {
        NavigationStack(path: $viewModel.importNavigationPath) {
            if let file = viewModel.csvFile {
                CSVColumnMappingView(
                    file: file,
                    mapping: $viewModel.columnMapping,
                    currentStep: 1,
                    totalSteps: totalSteps,
                    onContinue: { handleColumnMappingContinue() },
                    onCancel: { viewModel.cancelImport() }
                )
                .navigationDestination(for: ImportStep.self) { step in
                    switch step {
                    case .categoryMapping:
                        CSVCategoryMappingView(
                            csvCategories: viewModel.csvCategories,
                            categoryTypes: viewModel.csvCategoryTypes,
                            availableCategories: viewModel.availableCategories,
                            selections: $viewModel.categoryResolutionSelections,
                            currentStep: 2,
                            totalSteps: totalSteps,
                            onContinue: {
                                Task {
                                    await viewModel.applyMapping()
                                    viewModel.importNavigationPath.append(.results)
                                }
                            }
                        )
                    case .results:
                        ImportResultView(
                            rows: viewModel.mappedRows,
                            availableCategories: viewModel.availableCategories,
                            isImporting: viewModel.isImporting,
                            currentStep: importSteps,
                            totalSteps: totalSteps,
                            onConfirm: { viewModel.confirmImport($0) },
                            onDone: { viewModel.cancelImport() }
                        )
                    case .recurringSuggestions:
                        RecurrenceSuggestionsView(
                            viewModel: viewModel,
                            mode: .wizardStep(current: totalSteps, total: totalSteps)
                        )
                    }
                }
            } else if let workbook = viewModel.xlsxWorkbook {
                SheetPickerView(
                    sheetNames: workbook.sheetNames,
                    onSelect: { viewModel.selectSheet($0) },
                    onCancel: { viewModel.cancelImport() }
                )
            }
        }
        // ponytail: one line instead of a size-class branch — .page is already full-bleed on
        // iPhone, and on iPad it takes the whole window instead of a phone-width form sheet,
        // which is what was clipping the column preview to five columns.
        .presentationSizing(.page)
        // Same reason as iPad: losing a half-finished import to an accidental swipe is worse than
        // making people reach for Cancel.
        .interactiveDismissDisabled()
        .presentationBackground { AppBackground() }
    }

    private func handleColumnMappingContinue() {
        if viewModel.columnMapping.categoryColumn != nil {
            // Compute categories and types on background thread before navigating
            Task.detached(priority: .userInitiated) { [weak viewModel,
                                                       columnMapping = viewModel.columnMapping,
                                                       file = viewModel.csvFile] in
                guard let viewModel, let file else { return }
                let (categories, types) = CSVColumnMapper.extractCategoriesAndTypes(
                    from: file,
                    mapping: columnMapping
                )
                await MainActor.run {
                    viewModel.csvCategories = categories
                    viewModel.csvCategoryTypes = types
                    viewModel.applySavedCategorySelections()
                    viewModel.importNavigationPath.append(.categoryMapping)
                }
            }
        } else {
            viewModel.categoryResolutionSelections = [:]
            Task {
                await viewModel.applyMapping()
                viewModel.importNavigationPath.append(.results)
            }
        }
    }
}
