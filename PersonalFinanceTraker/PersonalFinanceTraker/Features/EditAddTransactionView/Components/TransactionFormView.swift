import SwiftUI
import SwiftData
import TipKit

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

/// Shows a keyboard-bar button's title beside its icon only where the bar has room for it:
/// iPad's spans the whole window, iPhone's is cramped enough that dropping those labels is
/// what created issue #31 in the first place.
///
/// One style taking a `Bool`, rather than `.labelStyle(cond ? .titleAndIcon : .iconOnly)` at
/// each call site — `TitleAndIconLabelStyle` and `IconOnlyLabelStyle` are distinct types, so
/// that ternary has no common type to resolve to and doesn't compile.
private struct KeyboardBarLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
            }
        } else {
            configuration.icon
        }
    }
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

    /// Drives the tip card, its scrim and the form's blur as one unit — see
    /// `syncTipVisibility()` for why this is stored state rather than a computed property.
    @State private var tipVisible = false

    // .popoverTip() doesn't anchor from the keyboard accessory bar — it lives in
    // UIRemoteKeyboardWindow, not the app window (verified on-device, issue #31).
    // Pinned above the accessory bar instead, via the .safeAreaInset below, so it
    // still reads as pointing at the row it explains rather than a card lost in
    // the scrolling form.
    @State private var tips = TipGroup(.ordered) {
        AddAnotherTip()
        RepeatTip()
        MathModeTip()
    }

    /// iPad shows this form in a persistent inspector column (`IPadInspector`) beside the
    /// dashboard, not as a sheet that owns the screen. Two things follow: the keyboard bar
    /// has room to label its buttons there, and the tips explaining those buttons — plus the
    /// scrim behind them — are skipped entirely. The controls themselves are identical on
    /// both platforms.
    ///
    /// Matches how `AuthenticationWrapper` picks the root view, so the two can't disagree
    /// about which layout is on screen.
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

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
                        if viewModel.isAmountFromScan {
                            ScannedValueCaption()
                        }
                        if !viewModel.receiptTotalCandidates.isEmpty {
                            ReceiptTotalCandidatesRow(
                                candidates: viewModel.receiptTotalCandidates,
                                currencyCode: viewModel.currencyCode,
                                onSelect: viewModel.selectReceiptTotalCandidate
                            )
                        }
                    } footer: {
                        if let status = viewModel.receiptStatusMessage {
                            Text(status)
                        }
                    }
                    .appFormSectionBackground()
                    .id(TransactionFormField.amount)

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
                                transactionType: viewModel.transactionType,
                                selectedCategory: $viewModel.selectedCategory,
                                onCategoryCreated: viewModel.selectCreatedCategory
                            )
                            // Category is always filled by a scan (even when guessed), so this is
                            // the one marker that's less "here's a value, check it" and more "this
                            // is a guess, please check it" — same caption either way, but it earns
                            // its keep most here.
                            if viewModel.isCategoryFromScan {
                                ScannedValueCaption()
                            }
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
                        if viewModel.isNameFromScan {
                            ScannedValueCaption()
                        }
                    }
                    .appFormSectionBackground()
                    .id(TransactionFormField.name)

                    Section {
                        DatePicker(
                            "Date",
                            selection: $viewModel.date,
                            displayedComponents: [.date]
                        )
                        .tint(.accentIndigo)
                        if viewModel.isDateFromScan {
                            ScannedValueCaption()
                        }
                    }
                    .appFormSectionBackground()

                }
                .appFormBackground()
                // Chevron taps go through `navigate` (scroll target into view, wait for the scroll
                // to actually settle, only then request focus) instead of setting focus directly —
                // same fix as AddGoalSheet's chevrons: a field currently scrolled out of the Form
                // doesn't reliably take focus from a bare FocusState assignment.
                .keyboardFieldNavigation($focusedField, order: [.amount, .name], hideDone: mathMode, hideFocusButtons: mathMode, navigate: { field in
                    withAnimation {
                        proxy.scrollTo(field, anchor: .center)
                    } completion: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            focusedField = field
                        }
                    }
                }) {
                    // Everything below is Amount-specific (Keep adding/Repeat only make sense at
                    // save time while entering the first field; the calculator only ever operates
                    // on the amount). Hidden (not removed) while Name is focused so it doesn't
                    // leak into the bar (#50) — removing it via `if` instead of `.opacity` made
                    // the whole capsule visibly narrow every time Name took focus, since a
                    // keyboard toolbar item sizes to its content's ideal width, not to whatever's
                    // available. Keeping the content structurally present and only toggling its
                    // visibility/interactivity keeps that ideal width constant.
                    let showsAmountContent = focusedField == .amount || mathMode
                    let isAddMode = viewModel.editingItem == nil
                    
                    if showsAmountContent {
                        Group {
                            // Save-time mode, not a form field — lives on the keyboard accessory bar
                            // instead, visible exactly while the keyboard the Add button used to sit
                            // above is open. Add mode only.
                            if !mathMode && isAddMode {
                                Button {
                                    viewModel.addAnother.toggle()
                                    AddAnotherTip().invalidate(reason: .actionPerformed)
                                } label: {
                                    // A Label, not a bare Image: the title is what iPad shows beside
                                    // the icon, and it doubles as the VoiceOver label this button was
                                    // missing (it previously announced the raw SF Symbol name).
                                    Label(
                                        "Keep adding",
                                        systemImage: viewModel.addAnother ? "plus.rectangle.fill.on.rectangle.fill" : "plus.rectangle.on.rectangle"
                                    )
                                }
                                .labelStyle(KeyboardBarLabelStyle(showsTitle: isPad))
                                .tint(viewModel.addAnother ? Color.accentIndigo : Color.primary)
                                .accessibilityValue(viewModel.addAnother ? String(localized: "On") : String(localized: "Off"))
                                
                                // Recurrence is a rare setup action, so it lives as a nav-bar toggle instead of taking
                                // inline form space. Add mode only, and not for transfers (recurring transfers are
                                // deferred — matches the type-change guard that also clears isRecurring).
                                if viewModel.transactionType != .transfer {
                                    Button {
                                        viewModel.isRecurring.toggle()
                                        RepeatTip().invalidate(reason: .actionPerformed)
                                    } label: {
                                        Label("Repeat", systemImage: viewModel.isRecurring ? "repeat.circle.fill" : "repeat.circle")
                                    }
                                    .labelStyle(KeyboardBarLabelStyle(showsTitle: isPad))
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
                                        MathModeTip().invalidate(reason: .actionPerformed)
                                        enterMathMode()
                                    }
                                }
                            } label: {
                                Label(
                                    mathMode ? String(localized: "Equal") : String(localized: "Math operation"),
                                    systemImage: mathMode ? "equal" : "plus.forwardslash.minus"
                                )
                            }
                            .labelStyle(KeyboardBarLabelStyle(showsTitle: isPad))
                            // Same on/off convention as the two toggles above: accent only while the
                            // mode is active. Without an explicit tint this fell through to the app's
                            // global AccentColor and sat permanently purple, reading as "on" next to
                            // two neutral siblings that were actually off.
                            .tint(mathMode ? Color.accentIndigo : Color.primary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                // Scoped to the Form on purpose: the scrim blocks taps on the rows behind the
                // tip, but the keyboard and its accessory bar render outside the Form, so the
                // controls the tip is explaining stay reachable.
                .focusScrim(tipVisible)
                // Pinned just above the accessory bar — appears exactly while the keyboard
                // (and the bar it explains) is up, and doesn't scroll away with the form.
                .safeAreaInset(edge: .bottom) {
                    if tipVisible, let tip = tips.currentTip {
                        TipView(tip)
                            .tipViewStyle(AppTipViewStyle())
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .padding(.bottom, 52)
                            .transition(.opacity)
                    }
                }
                // Both inputs to tipVisible have to be watched: focus and TipKit's currentTip
                // resolve in separate render passes, and syncTipVisibility() folds whichever
                // lands second into one animated transaction.
                .onChange(of: focusedField) { _, field in
                    syncTipVisibility()
                    // Tapping straight onto another field (Name) while the calculator's up
                    // bypasses the chevrons/Done entirely — those are hidden in math mode — so
                    // nothing else ever told math mode to end. Without this, showsAmountContent
                    // (gated on `mathMode`, not on focus) kept the bubble/operator row showing
                    // long after Amount lost focus. Commits whatever's typed, same as "=".
                    if mathMode, field != .mathExpression, field != .amount {
                        commitMathExpression(restoringFocus: false)
                    }
                    // Scrolls whichever field just took focus above the keyboard — without this
                    // the Name row, several sections down, stayed hidden behind it (#54). Skipped
                    // for .mathExpression: that bubble lives inline in the keyboard bar itself,
                    // not a row in the Form, so there's nothing to scroll to.
                    guard let field, field != .mathExpression else { return }
                    // .top, not .center: centering only leaves room for the raw keyboard, not the
                    // extra ~40-70pt the custom accessory bar (chevrons/Done, plus the Amount-only
                    // row) adds above it — a field centered in what Form thinks is the visible
                    // area can still end up right behind that bar. Anchoring to the row's top edge
                    // leaves the whole remaining viewport height below it as clearance instead.
                    withAnimation { proxy.scrollTo(field, anchor: .top) }
                }
                .onChange(of: tips.currentTip?.id) { _, _ in syncTipVisibility() }
                .onChange(of: focusTrigger) { _, _ in
                    // After an "Add another" save the form resets in place; snap back to the top
                    // (blank Amount) so the user isn't left at the bottom of the sheet. Fires on the
                    // same token bump that clears/re-focuses the amount field.
                    withAnimation { proxy.scrollTo(TransactionFormField.amount, anchor: .top) }
                }
                .onAppear {
                    updateTipEligibility()
                    syncTipVisibility()
                }
                .onChange(of: viewModel.transactionType) { _, _ in updateTipEligibility() }
            }
        }
    }

    /// Folds the two independent inputs — keyboard focus and TipKit's async `currentTip` —
    /// into one animated state change.
    ///
    /// A computed property read directly by the blur/overlay/inset was tried first and
    /// animated badly: focus and `currentTip` land in *separate* render passes, so an
    /// outer `.animation(_:value:)` caught the blur's radius interpolation but missed the
    /// structural insertion of the card and scrim — they snapped in at full opacity a
    /// frame ahead of the blur (confirmed frame-by-frame). Committing one `@State` flip
    /// inside an explicit `withAnimation` puts all three in the same transaction.
    private func syncTipVisibility() {
        // One gate for the card and its scrim both. Nothing to explain on iPad — the keyboard
        // bar spells each button out there (see `KeyboardBarLabelStyle`), so a tip would be
        // captioning a control that already says what it does. The scrim was wrong there
        // independently: it dims this Form, which on iPad is one column of a split layout, so
        // the untouched columns beside it end up brighter than the tip it was spotlighting.
        let shouldShow = !isPad && focusedField != nil && tips.currentTip != nil
        guard shouldShow != tipVisible else { return }
        withAnimation(.easeInOut(duration: 0.25)) { tipVisible = shouldShow }
    }

    /// Keeps the two gated tips' eligibility in step with their buttons' own visibility
    /// conditions, so `TipGroup`'s order can't land on a tip for a control that isn't
    /// rendered (e.g. opening the sheet in edit mode, or switching to Transfer).
    private func updateTipEligibility() {
        AddAnotherTip.isEligible = viewModel.editingItem == nil
        RepeatTip.isEligible = viewModel.editingItem == nil && viewModel.transactionType != .transfer
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
    /// - Parameter restoringFocus: true for the "=" button, which needs to hand focus back to
    ///   Amount itself. False when called because focus already moved elsewhere (tapping
    ///   straight onto another field while the calculator's up) — forcing it back to Amount
    ///   there would fight whatever the user just tapped.
    private func commitMathExpression(restoringFocus: Bool = true) {
        guard !mathExpression.isEmpty else {
            exitMathMode(restoringFocus: restoringFocus)
            return
        }
        guard let result = MathExpressionEvaluator.evaluate(mathExpression) else { return }
        // `amount` is a magnitude (CurrencyAmountField itself only ever accepts >= 0); the
        // expense/income sign lives in the Type picker, not here.
        viewModel.amount = abs(result)
        exitMathMode(restoringFocus: restoringFocus)
    }

    private func exitMathMode(restoringFocus: Bool = true) {
        mathMode = false
        mathExpression = ""
        if restoringFocus { focusedField = .amount }
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

// MARK: - Receipt scan

/// The "this came from a scan, check it" marker — same caption under Amount, Category, Name, and
/// Date. Icon + text (never color alone) so it still reads under Differentiate Without Color, and
/// it disappears on its own the moment the bound value changes: the view models' `is*FromScan`
/// flags are equality checks against what the scan wrote, not a manually-cleared touched flag.
private struct ScannedValueCaption: View {
    var body: some View {
        Label("Scanned — check before saving", systemImage: "sparkles")
            .font(.caption)
            .foregroundStyle(.textMid)
    }
}

/// Shown under Amount only when the parser found several disagreeing total-keyword lines (the
/// CONTANTI-style ambiguity) — picking one clears the row and fills Amount, marked as scanned.
private struct ReceiptTotalCandidatesRow: View {
    let candidates: [Decimal]
    let currencyCode: String
    let onSelect: (Decimal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Which total is right?")
                .font(.subheadline)
                .foregroundStyle(.textMid)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(candidates, id: \.self) { candidate in
                        Button(AmountParser.format(candidate, currencyCode: currencyCode)) {
                            onSelect(candidate)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Category Chips Grid

struct CategoryChipsGrid: View {
    let categories: [CategorySnapshot]
    let transactionType: TransactionType
    @Binding var selectedCategory: CategorySnapshot?
    let onCategoryCreated: (CategorySnapshot) -> Void
    @Query(sort: \CategoryModel.name) private var existingCategories: [CategoryModel]
    @State private var showAll = false
    @State private var showAddCategory = false
    @State private var openAddCategoryAfterPickerDismiss = false

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

    // Compact single-row horizontal scroller instead of a multi-row grid: a required field that
    // must stay reachable above the keyboard shouldn't cost several rows of vertical space. The
    // most-used categories come first (see filteredCategories), the selection auto-scrolls into
    // view, and the "More…" chip opens the full searchable list plus category creation.
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
                    MoreChip { showAll = true }
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
        .sheet(isPresented: $showAll, onDismiss: openPendingAddCategorySheet) {
            CategoryPickerSheet(
                categories: categories,
                selectedCategory: $selectedCategory,
                onAddCategory: {
                    openAddCategoryAfterPickerDismiss = true
                    showAll = false
                }
            )
        }
        .sheet(isPresented: $showAddCategory) {
            AddCategorySheet(existingCategories: existingCategories, initialType: transactionType) { category in
                let snapshot = CategorySnapshot(category)
                onCategoryCreated(snapshot)
                selectedCategory = snapshot
            }
        }
    }

    private func openPendingAddCategorySheet() {
        guard openAddCategoryAfterPickerDismiss else { return }
        openAddCategoryAfterPickerDismiss = false
        showAddCategory = true
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
    let onAddCategory: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    init(
        categories: [CategorySnapshot],
        selectedCategory: Binding<CategorySnapshot?>,
        onAddCategory: @escaping () -> Void = {}
    ) {
        self.categories = categories
        _selectedCategory = selectedCategory
        self.onAddCategory = onAddCategory
    }

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Category", systemImage: "plus") {
                        dismiss()
                        onAddCategory()
                    }
                    .font(.headline)
                    .foregroundStyle(.accentIndigo)
                    .glassEffect(.regular.interactive())
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
