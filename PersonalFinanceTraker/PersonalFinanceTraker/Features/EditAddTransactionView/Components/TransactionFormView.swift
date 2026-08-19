import SwiftUI

/// The form's text fields, in tab order. Only the typed ones: pickers, chips and the date wheel are
/// reached by tapping, and putting them in the chain would mean "Next" sometimes dismisses the
/// keyboard for no visible reason.
enum TransactionFormField: CaseIterable, Hashable {
    case amount
    case name
    /// The calculator bubble. Kept as a case of this same enum — not a second `@FocusState`
    /// property — so switching into/out of math mode is a single atomic focus reassignment.
    /// Two separate `FocusState`s each resigning/becoming first responder on their own pass
    /// makes the keyboard fully dismiss and reappear in between (a visible flash, the form
    /// reflowing to show the rows underneath) instead of one continuous swap.
    case mathExpression
}

struct TransactionFormView: View {
    @Bindable var viewModel: EditAddTransactionViewModel
    var focusTrigger: Int = 0
    @State var mathMode: Bool = false
    /// The calculator bubble's raw text (e.g. "(500+504)×6÷8") — a separate field from
    /// `viewModel.amount`, not a reformatting of it, so the amount field's own parsing
    /// (currency formatting, hidden-amounts blur) never has to understand operator characters.
    @State private var mathExpression: String = ""

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

                }
                .appFormBackground()
                .keyboardFieldNavigation($focusedField, order: [.amount, .name], hideDone: mathMode, hideFocusButtons: mathMode) {
                    // Save-time mode, not a form field — lives on the keyboard accessory bar
                    // instead, visible exactly while the keyboard the Add button used to sit
                    // above is open. Add mode only.
                    Spacer()
                    if !mathMode {
                        if viewModel.editingItem == nil {
                            Button {
                                viewModel.addAnother.toggle()
                            } label: {
                                Image(systemName: viewModel.addAnother ? "plus.rectangle.fill.on.rectangle.fill" : "plus.rectangle.on.rectangle")
                            }
                            .tint(viewModel.addAnother ? Color.accentIndigo : Color.primary)
                            .accessibilityValue(viewModel.addAnother ? String(localized: "On") : String(localized: "Off"))
                        }
                        // Recurrence is a rare setup action, so it lives as a nav-bar toggle instead of taking
                        // inline form space. Add mode only, and not for transfers (recurring transfers are
                        // deferred — matches the type-change guard that also clears isRecurring).
                        if viewModel.editingItem == nil && viewModel.transactionType != .transfer {
                            Button {
                                viewModel.isRecurring.toggle()
                            } label: {
                                Label("Repeat", systemImage: viewModel.isRecurring ? "repeat.circle.fill" : "repeat.circle")
                            }
                            // Indigo only when on; a neutral glyph when off so the toolbar button doesn't
                            // read as "active" while recurrence is actually off.
                            .tint(viewModel.isRecurring ? Color.accentIndigo : Color.primary)
                            .accessibilityValue(viewModel.isRecurring ? String(localized: "On") : String(localized: "Off"))
                        }
                    }
                    
                    if mathMode {
                        // The expression bubble is a real (small, borderless) TextField, not a
                        // label: digits always go wherever the system keyboard's current focus
                        // is, so this — not viewModel.amount — has to be the focused control
                        // while calculating, or typed digits would have nowhere to land.
                        TextField("0", text: expressionDisplayBinding)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .mathExpression)
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1)
                            .frame(minWidth: 60, maxWidth: 140)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.surfaceRaised, in: Capsule())

                        operatorButton("+", systemImage: "plus", accessibilityLabel: "Add")
                        operatorButton("-", systemImage: "minus", accessibilityLabel: "Subtract")
                        operatorButton("×", systemImage: "multiply", accessibilityLabel: "Multiply")
                        operatorButton("÷", systemImage: "divide", accessibilityLabel: "Divide")
                    }

                    Button {
                        withAnimation {
                            if mathMode {
                                commitMathExpression()
                            } else {
                                enterMathMode()
                            }
                        }
                    } label: {
                        Label(
                            mathMode ? String(localized: "Equal") : String(localized: "Math operation"),
                            systemImage: mathMode ? "equal" : "plus.forwardslash.minus"
                        )
                    }
                }
                .onChange(of: focusTrigger) { _, _ in
                    // After an "Add another" save the form resets in place; snap back to the top
                    // (blank Amount) so the user isn't left at the bottom of the sheet. Fires on the
                    // same token bump that clears/re-focuses the amount field.
                    withAnimation { proxy.scrollTo("formTop", anchor: .top) }
                }
            }
        }
    }

    /// Live-formatted view of `mathExpression` for the bubble — parens are decorative (this
    /// bubble has no paren key), so editing through here just strips them back out; the flat
    /// string in `mathExpression` itself — what `appendOperator`/`commitMathExpression` actually
    /// work with — is unaffected either way.
    ///
    /// Known trade-off: the displayed text can grow/shrink by more than the one character the
    /// user typed (a paren appearing, or shifting position), so the cursor can occasionally snap
    /// to the end after a keystroke instead of staying mid-string. Acceptable here since this is
    /// calculator-style entry — type/backspace at the end — not a field people routinely
    /// reposition a cursor inside.
    private var expressionDisplayBinding: Binding<String> {
        Binding(
            get: { MathExpressionEvaluator.liveFormatted(mathExpression) },
            set: { mathExpression = $0.filter { $0 != "(" && $0 != ")" } }
        )
    }

    private func operatorButton(_ symbol: String, systemImage: String, accessibilityLabel: LocalizedStringKey) -> some View {
        Button {
            appendOperator(symbol)
        } label: {
            Image(systemName: systemImage)
        }
        .tint(Color.primary)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Seeds the bubble from the amount already typed (if any) so tapping into math mode
    /// extends what's there instead of discarding it, then moves keyboard focus to the bubble.
    /// One assignment to the shared `focusedField` — not a second FocusState — so the keyboard
    /// swaps directly onto the bubble instead of dismissing and reappearing.
    private func enterMathMode() {
        mathExpression = viewModel.amount > 0 ? plainString(viewModel.amount) : ""
        mathMode = true
        focusedField = .mathExpression
    }

    /// Appends an operator, replacing a trailing one instead of stacking ("5+" tap "×" → "5×")
    /// — the obvious behavior for correcting a mis-tap, and it costs nothing extra to support.
    private func appendOperator(_ op: String) {
        if mathExpression.isEmpty {
            if op == "-" { mathExpression = op }  // leading minus = negative number; the rest need a left side
            return
        }
        if let last = mathExpression.last, "+-×÷".contains(last) {
            mathExpression.removeLast()
        }
        mathExpression.append(op)
    }

    /// The same button doubles as "=" once math mode is on. An empty bubble has nothing to
    /// compute, so treat that tap as "never mind" and just exit rather than no-op silently.
    /// A non-empty but unparseable expression is left alone (stays in math mode) so the user
    /// can fix it — `MathExpressionEvaluator` never throws, so there's nothing to catch here.
    private func commitMathExpression() {
        guard !mathExpression.isEmpty else {
            exitMathMode()
            return
        }
        guard let result = MathExpressionEvaluator.evaluate(mathExpression) else { return }
        // `amount` is a magnitude (CurrencyAmountField itself only ever accepts >= 0); the
        // expense/income sign lives in the Type picker, not here.
        viewModel.amount = abs(result)
        exitMathMode()
    }

    private func exitMathMode() {
        mathMode = false
        mathExpression = ""
        focusedField = .amount
    }

    /// Plain (non-currency) decimal string for seeding the bubble — same convention
    /// `CurrencyAmountField` uses for its own editing text, duplicated rather than exposed
    /// since it's a few lines and that view's formatting is private/internal to it.
    private func plainString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = Locale.current.decimalSeparator ?? ","
        formatter.groupingSeparator = ""
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? ""
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
