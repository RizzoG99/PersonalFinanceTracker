import SwiftUI

/// The form's text fields, in tab order. Only the typed ones: pickers, chips and the date wheel are
/// reached by tapping, and putting them in the chain would mean "Next" sometimes dismisses the
/// keyboard for no visible reason.
enum TransactionFormField: CaseIterable, Hashable {
    case amount
    case name
}

struct TransactionFormView: View {
    @Bindable var viewModel: EditAddTransactionViewModel
    var focusTrigger: Int = 0

    @Environment(\.verticalSizeClass) private var vSizeClass
    @FocusState private var focusedField: TransactionFormField?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        CurrencyAmountField(
                            label: "Amount",
                            placeholder: "0",
                            amount: $viewModel.amount,
                            currencyCode: $viewModel.currencyCode,
                            shouldAutoFocus: viewModel.shouldAutoFocusAmount,
                            focusTrigger: focusTrigger,
                            focus: $focusedField
                        )
                    }
                    .appFormSectionBackground()
                    .id("formTop")

                    Section {
                        Picker("Type", selection: $viewModel.transactionType) {
                            ForEach(viewModel.availableTypes, id: \.self) { type in
                                Text(String(localized: String.LocalizationValue(type.rawValue))).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: viewModel.transactionType) { _, newType in
                            viewModel.selectedCategory = nil
                            viewModel.selectedGoal = nil
                            if newType == .transfer { viewModel.isRecurring = false }
                        }
                    }
                    .appFormSectionBackground()

                    // Recurrence detail reveals up top (only when the toolbar Repeat toggle is on).
                    // The toggle itself lives in the nav bar; this section is just its sub-options.
                    if viewModel.editingItem == nil && viewModel.transactionType != .transfer && viewModel.isRecurring {
                        Section {
                            Picker("Frequency", selection: $viewModel.recurrenceFrequency) {
                                ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                                    Text(freq.label).tag(freq)
                                }
                            }
                            .onChange(of: viewModel.recurrenceFrequency) { _, newFrequency in
                                viewModel.recurrenceInterval = min(viewModel.recurrenceInterval, newFrequency.maxInterval)
                            }
                            Stepper(
                                "Every \(viewModel.recurrenceInterval) \(viewModel.recurrenceFrequency.unitLabel(for: viewModel.recurrenceInterval))",
                                value: $viewModel.recurrenceInterval,
                                in: 1...viewModel.recurrenceFrequency.maxInterval
                            )
                        } header: {
                            Text("Repeat")
                        }
                        .appFormSectionBackground()
                    }

                    // Category/Goal is required, so it sits right after Type (required-before-optional)
                    // and stays visible without scrolling past the optional Name/Date rows below.
                    if viewModel.transactionType == .transfer {
                        Section {
                            GoalChipsGrid(
                                availableGoals: viewModel.availableGoals,
                                selectedGoal: $viewModel.selectedGoal
                            )
                        } header: {
                            Text("Goal")
                        }
                        .appFormSectionBackground()
                    } else {
                        Section {
                            CategoryChipsGrid(
                                categories: viewModel.filteredCategories,
                                selectedCategory: $viewModel.selectedCategory
                            )
                        } header: {
                            Text("Category")
                        }
                        .appFormSectionBackground()
                    }

                    // Name is optional, so it follows the required Category (required-before-optional).
                    Section {
                        TextField("Name", text: $viewModel.transactionName, prompt: Text("Name (optional)"))
                            .focused($focusedField, equals: .name)
                            // .next promised a next field and delivered nothing — this is the last
                            // one in the chain.
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    }
                    .appFormSectionBackground()

                    Section {
                        DatePicker(
                            "Date",
                            selection: $viewModel.date,
                            displayedComponents: [.date]
                        )
                        .tint(.accentIndigo)
                    }
                    .appFormSectionBackground()

                    // "Add another" is normally NOT in the form: it's a save-time mode, pinned above
                    // the Add Transaction button in EditAddTransactionView's persistent action zone.
                    // That zone doesn't exist in landscape (the keyboard owns the bottom), so the
                    // toggle falls back to being a form row rather than disappearing.
                    if vSizeClass == .compact && viewModel.editingItem == nil {
                        Section {
                            Toggle("Add another", isOn: $viewModel.addAnother)
                                .tint(.accentIndigo)
                        }
                        .appFormSectionBackground()
                    }
                }
                .appFormBackground()
                .keyboardFieldNavigation($focusedField, order: TransactionFormField.allCases)
                .onChange(of: focusTrigger) { _, _ in
                    // After an "Add another" save the form resets in place; snap back to the top
                    // (blank Amount) so the user isn't left at the bottom of the sheet. Fires on the
                    // same token bump that clears/re-focuses the amount field.
                    withAnimation { proxy.scrollTo("formTop", anchor: .top) }
                }
            }
        }
    }
}

// MARK: - Category Chips Grid

struct CategoryChipsGrid: View {
    let categories: [CategorySnapshot]
    @Binding var selectedCategory: CategorySnapshot?
    @State private var showAll = false

    /// How many most-used categories to show inline before the "More…" chip. The rest live behind
    /// the full searchable picker so the strip stays short instead of scrolling the whole list.
    private let maxInline = 5

    // Only the top few (most-used first) show inline; the current selection is always included even
    // if it ranks below the cutoff, so the chosen chip stays visible.
    private var inlineCategories: [CategorySnapshot] {
        let top = Array(categories.prefix(maxInline))
        if let sel = selectedCategory,
           categories.contains(where: { $0.id == sel.id }),
           !top.contains(where: { $0.id == sel.id }) {
            return top + [sel]
        }
        return top
    }

    // Only surface "More…" when it actually reveals categories not already shown inline.
    private var hasMore: Bool { categories.count > inlineCategories.count }

    // Compact single-row horizontal scroller instead of a multi-row grid: a required field that
    // must stay reachable above the keyboard shouldn't cost several rows of vertical space. The
    // most-used categories come first (see filteredCategories), the selection auto-scrolls into
    // view, and the "More…" chip opens the full searchable list.
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(inlineCategories) { category in
                        CategoryChip(
                            category: category,
                            isSelected: selectedCategory?.persistentId == category.persistentId
                        )
                        .id(category.id)
                        .onTapGesture {
                            selectedCategory = category
                        }
                    }
                    if hasMore {
                        MoreChip { showAll = true }
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: selectedCategory?.id) { _, id in
                // Keep the current selection visible; on reset (nil) return to the start.
                if let id {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                } else if let first = inlineCategories.first {
                    withAnimation { proxy.scrollTo(first.id, anchor: .leading) }
                }
            }
        }
        .sheet(isPresented: $showAll) {
            CategoryPickerSheet(categories: categories, selectedCategory: $selectedCategory)
        }
    }
}

/// Chip-styled button that opens the full category list. Matches CategoryChip's footprint so it
/// sits flush at the end of the horizontal strip.
struct MoreChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .foregroundStyle(.textPrimary)
                    .frame(height: 24)  // match CategoryChip's icon row so heights line up
                Text("More")
                    .font(.caption2)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.textPrimary)
            }
            .frame(width: 84)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.textDim.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

/// Full, searchable category grid — the "More…" escape hatch behind the compact strip.
struct CategoryPickerSheet: View {
    let categories: [CategorySnapshot]
    @Binding var selectedCategory: CategorySnapshot?
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [CategorySnapshot] {
        guard !search.isEmpty else { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(filtered) { category in
                        CategoryChip(
                            category: category,
                            isSelected: selectedCategory?.persistentId == category.persistentId
                        )
                        .onTapGesture {
                            selectedCategory = category
                            dismiss()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: Text("Search categories"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground { AppBackground() }
    }
}

struct CategoryChip: View {
    let category: CategorySnapshot
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: category.systemImage)
                .font(.system(size: 20))
                .foregroundStyle(category.categoryColor)
                .frame(height: 24)  // fixed icon row so every chip is the same height

            Text(category.name.localizedCategoryDisplay)
                .font(.caption2)
                // Reserve 2 lines even for 1-line labels so every chip is the same height.
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .foregroundStyle(.textPrimary)
        }
        // Fixed width so chips line up in the horizontal scroller (was maxWidth:.infinity for the grid).
        .frame(width: 84)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            isSelected
                ? category.categoryColor.opacity(0.2)
                : Color.clear
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? category.categoryColor : Color.textDim.opacity(0.3),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .cornerRadius(12)
    }
}

// MARK: - Goal Chips Grid

struct GoalChipsGrid: View {
    let availableGoals: [GoalSnapshot]
    @Binding var selectedGoal: GoalSnapshot?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableGoals) { goal in
                        GoalChip(
                            goal: goal,
                            isSelected: selectedGoal?.id == goal.id
                        )
                        .id(goal.id)
                        .onTapGesture {
                            selectedGoal = goal
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: selectedGoal?.id) { _, id in
                if let id {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                } else if let first = availableGoals.first {
                    withAnimation { proxy.scrollTo(first.id, anchor: .leading) }
                }
            }
        }
    }
}

struct GoalChip: View {
    let goal: GoalSnapshot
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: goal.iconName)
                .font(.system(size: 20))
                .foregroundStyle(goal.goalColor)
                .frame(height: 24)  // fixed icon row so every chip is the same height

            Text(goal.name)
                .font(.caption2)
                // Reserve 2 lines even for 1-line labels so every chip is the same height.
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .foregroundStyle(.textPrimary)
        }
        // Fixed width so chips line up in the horizontal scroller (was maxWidth:.infinity for the grid).
        .frame(width: 84)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            isSelected
                ? goal.goalColor.opacity(0.2)
                : Color.clear
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? goal.goalColor : Color.textDim.opacity(0.3),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .cornerRadius(12)
    }
}
