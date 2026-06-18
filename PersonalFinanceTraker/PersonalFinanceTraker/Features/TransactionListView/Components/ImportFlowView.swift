//
//  ImportFlowView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct ImportFlowView: View {
    @Bindable var viewModel: TransactionListViewModel

    var body: some View {
        NavigationStack(path: $viewModel.importNavigationPath) {
            if let file = viewModel.csvFile {
                CSVColumnMappingView(
                    file: file,
                    mapping: $viewModel.columnMapping,
                    onContinue: { handleColumnMappingContinue() }
                )
                .navigationDestination(for: ImportStep.self) { step in
                    switch step {
                    case .categoryMapping:
                        let cats = viewModel.csvFile.map {
                            CSVColumnMapper.uniqueCategories(from: $0, mapping: viewModel.columnMapping)
                        } ?? []
                        CSVCategoryMappingView(
                            csvCategories: cats,
                            categoryTypes: inferCategoryTypes(cats),
                            availableCategories: viewModel.availableCategories,
                            resolution: $viewModel.categoryResolution,
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
                            onConfirm: { viewModel.confirmImport($0) }
                        )
                    }
                }
            }
        }
    }

    private func handleColumnMappingContinue() {
        if viewModel.columnMapping.categoryColumn != nil {
            viewModel.importNavigationPath.append(.categoryMapping)
        } else {
            viewModel.categoryResolution = [:]
            Task {
                await viewModel.applyMapping()
                viewModel.importNavigationPath.append(.results)
            }
        }
    }

    /// Determines income vs expense for each unique CSV category by scanning the type column.
    private func inferCategoryTypes(_ csvCategories: [String]) -> [String: TransactionType] {
        guard let file = viewModel.csvFile,
              let typeCol = viewModel.columnMapping.typeColumn,
              let catCol = viewModel.columnMapping.categoryColumn,
              let typeIdx = file.columnIndex(for: typeCol),
              let catIdx = file.columnIndex(for: catCol) else {
            return [:]
        }
        var result: [String: TransactionType] = [:]
        file.processRows { row in
            guard catIdx < row.count, typeIdx < row.count else { return }
            let cat = row[catIdx].trimmingCharacters(in: .whitespaces)
            guard !cat.isEmpty, result[cat] == nil else { return }
            let lower = row[typeIdx].lowercased()
            let isIncome = lower.contains("inc") || lower.contains("income") ||
                           lower.contains("entrata") || lower.contains("credit")
            result[cat] = isIncome ? .income : .expense
        }
        return result
    }
}
