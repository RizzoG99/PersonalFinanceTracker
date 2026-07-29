//
//  ImportFlowView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct ImportFlowView: View {
    @Bindable var viewModel: TransactionListViewModel

    private var totalSteps: Int {
        viewModel.columnMapping.categoryColumn != nil ? 3 : 2
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
                            isImporting: viewModel.isImporting,
                            currentStep: totalSteps,
                            totalSteps: totalSteps,
                            onConfirm: { viewModel.confirmImport($0) },
                            onDone: { viewModel.cancelImport() }
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
        .presentationBackground { AppBackground() }
    }

    private func handleColumnMappingContinue() {
        if viewModel.columnMapping.categoryColumn != nil {
            // Compute categories and types on background thread before navigating
            Task.detached(priority: .userInitiated) { [weak viewModel, columnMapping = viewModel.columnMapping] in
                guard let viewModel = viewModel,
                      let file = viewModel.csvFile else { return }
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
