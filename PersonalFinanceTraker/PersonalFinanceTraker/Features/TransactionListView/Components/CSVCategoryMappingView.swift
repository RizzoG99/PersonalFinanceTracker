//
//  CSVCategoryMappingView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CSVCategoryMappingView: View {
    let csvCategories: [String]
    /// Inferred income/expense type for each CSV category. Nil = unknown (show all).
    let categoryTypes: [String: TransactionType]
    let availableCategories: [CategorySnapshot]
    @Binding var selections: [String: String]
    let currentStep: Int
    let totalSteps: Int
    let onContinue: () -> Void
    /// See CSVColumnMappingView: false in the iPad two-pane layout, which has no next step.
    var showsStepActions: Bool = true

    @Environment(TransactionListViewModel.self) private var viewModel
    @State private var categoryBeingConfigured: ImportCategoryDraft?

    /// See ImportResultView.barTitle — every pane embedded in the iPad sheet's one bar must
    /// agree on the title.
    private var barTitle: LocalizedStringKey {
        showsStepActions ? "Map Categories" : "Import"
    }

    private let newSentinel = "__new__"

    private var allMapped: Bool {
        csvCategories.allSatisfy { selections[$0] != nil }
    }

    private var unmappedCount: Int {
        csvCategories.filter { selections[$0] == nil }.count
    }

    /// Mirrors CSVColumnMappingView's canContinueBanner so both steps say "you're not done" the
    /// same way.
    private var unmappedBanner: some View {
        Label {
            // ponytail: "category"/"categories" plural handled by the catalog's plural variation, not a hand-rolled ternary
            Text("Map all \(unmappedCount) remaining category to continue.")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.footnote)
        .foregroundStyle(Color.negative)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    var body: some View {
        List {
            // Plain copy, not a filled card: a card is chrome for controls, and giving one sentence
            // of guidance the same weight as the rows below it made the pane look like it opened on
            // an empty panel. The unmapped-count warning moved to a pinned banner, matching step 1 —
            // as a footer here it scrolled out of sight exactly when it mattered.
            Text("Map each CSV category to an existing app category, or create a new one.")
                .font(.footnote)
                .foregroundStyle(.textDim)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            let expenseCategories = csvCategories.filter { categoryTypes[$0] != .income }
            let incomeCategories  = csvCategories.filter { categoryTypes[$0] == .income }

            if !expenseCategories.isEmpty {
                Section("Expenses (\(expenseCategories.count))") {
                    ForEach(expenseCategories, id: \.self) { csv in
                        categoryRow(for: csv)
                    }
                }
                .appFormSectionBackground()
            }
            if !incomeCategories.isEmpty {
                Section("Income (\(incomeCategories.count))") {
                    ForEach(incomeCategories, id: \.self) { csv in
                        categoryRow(for: csv)
                    }
                }
                .appFormSectionBackground()
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            if !allMapped {
                unmappedBanner
            }
        }
        // The sheet's presentationBackground only reaches the NavigationStack's root (step 1);
        // pushed destinations get their own opaque host, so each one paints the gradient itself.
        .appBackground()
        .navigationTitle(barTitle)
        .navigationSubtitle(showsStepActions ? "Step \(currentStep) of \(totalSteps)" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Trailing, not leading: leading is the pushed view's back button, and crowding it is
            // how you get users tapping Auto-Map when they meant to go back.
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { autoMap() }) {
                    Label("Auto-Map All", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
            }
            if showsStepActions {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Continue") { buildResolutionAndContinue() }
                        .bold()
                        .disabled(!allMapped)
                }
            }
        }
        .onAppear {
            // Auto-map on first appear only (guard against re-running on back-nav)
            if !viewModel.hasAutoMappedCategories {
                autoMap()
                viewModel.hasAutoMappedCategories = true
            }
        }
        .sheet(item: $categoryBeingConfigured) { draft in
            ImportCategorySetupSheet(
                draft: draft,
                lockedType: categoryTypes[draft.csvCategory],
                existingNames: Set(availableCategories.map { $0.name.lowercased() }),
                otherDraftNames: Set(
                    viewModel.pendingCategoryDrafts
                        .filter { $0.key != draft.csvCategory }
                        .map { $0.value.name.trimmingCharacters(in: .whitespaces).lowercased() }
                ),
                onSave: { savedDraft in
                    viewModel.pendingCategoryDrafts[savedDraft.csvCategory] = savedDraft
                    selections[savedDraft.csvCategory] = newSentinel
                }
            )
        }
    }

    // MARK: - Row

    private func categoryRow(for csv: String) -> some View {
        // The emoji is part of the CSV's own category name, so it stays on screen; only the
        // emoji-only case needs help, and the only honest help is saying it has no name.
        let isUnnamed = csv.removingLeadingEmoji.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack {
            Text(isUnnamed ? "\(csv) (unnamed)" : "\(csv)")
                .font(.subheadline)
                .accessibilityLabel(isUnnamed ? Text("Unnamed category") : Text(csv))

            Spacer()

            Menu {
                let knownType = categoryTypes[csv]
                let filtered = filteredCategories(for: knownType).sorted { $0.name < $1.name }

                if knownType == nil {
                    // Type unknown — show both sections
                    let income  = filtered.filter { $0.transactionType == .income }
                    let expense = filtered.filter { $0.transactionType == .expense }
                    if !income.isEmpty {
                        Section("Income") {
                            ForEach(income) { cat in
                                Button { selectExisting(cat, for: csv) } label: {
                                    Label(cat.name.localizedCategoryDisplay, systemImage: cat.systemImage)
                                }
                            }
                        }
                    }
                    if !expense.isEmpty {
                        Section("Expense") {
                            ForEach(expense) { cat in
                                Button { selectExisting(cat, for: csv) } label: {
                                    Label(cat.name.localizedCategoryDisplay, systemImage: cat.systemImage)
                                }
                            }
                        }
                    }
                } else {
                    // Type known — flat sorted list
                    ForEach(filtered) { cat in
                        Button { selectExisting(cat, for: csv) } label: {
                            Label(cat.name.localizedCategoryDisplay, systemImage: cat.systemImage)
                        }
                    }
                }
                Divider()
                Button {
                    configureNewCategory(for: csv)
                } label: {
                    Label {
                        if selections[csv] == newSentinel {
                            Text("Edit \"\(createName(for: csv))\"")
                        } else {
                            Text("Create \"\(createName(for: csv))\"")
                        }
                    } icon: {
                        Image(systemName: selections[csv] == newSentinel ? "pencil" : "plus.circle")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if let sel = selections[csv] {
                        if sel == newSentinel {
                            Group {
                                if let draft = viewModel.pendingCategoryDrafts[csv] {
                                    Text(draft.name)
                                } else {
                                    Text("Create \"\(createName(for: csv))\"")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.accentIndigo)
                        } else if let cat = availableCategories.first(where: { $0.id.uuidString == sel }) {
                            Text(cat.name.localizedCategoryDisplay)
                                .font(.subheadline)
                                .foregroundStyle(.accentIndigo)
                        }
                    } else {
                        Text("Select…")
                            .font(.subheadline)
                            .foregroundStyle(.accentIndigo)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    /// Falls back to the raw value: an emoji-only category strips to nothing, and `Create ""` tells
    /// the user less than the emoji does.
    private func createName(for csv: String) -> String {
        let stripped = csv.removingLeadingEmoji.trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? csv : stripped
    }

    /// Returns categories filtered to the matching type, or all if type is unknown.
    private func filteredCategories(for type: TransactionType?) -> [CategorySnapshot] {
        guard let type else { return availableCategories }
        return availableCategories.filter { $0.transactionType == type }
    }

    // MARK: - Actions

    private func buildResolutionAndContinue() {
        // Selections already contain the choices (UUID strings or the new-category sentinel).
        // Actual category creation happens in confirmImport; nothing to do here except continue.
        onContinue()
    }

    private func selectExisting(_ category: CategorySnapshot, for csv: String) {
        viewModel.pendingCategoryDrafts[csv] = nil
        selections[csv] = category.id.uuidString
    }

    private func configureNewCategory(for csv: String) {
        categoryBeingConfigured = viewModel.pendingCategoryDrafts[csv]
            ?? ImportCategoryDraft(csvCategory: csv, inferredType: categoryTypes[csv])
    }

    private func autoMap() {
        selections = CategoryAutoMapper.resolve(
            csvCategories: csvCategories,
            categoryTypes: categoryTypes,
            availableCategories: availableCategories,
            existing: selections
        )
    }
}
