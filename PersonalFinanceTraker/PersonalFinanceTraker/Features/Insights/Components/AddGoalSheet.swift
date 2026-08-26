//
//  AddGoalSheet.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct AddGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_base_currency") private var currencyCode = "EUR"
    /// Landscape iPhone gives this sheet ~370pt, and the keyboard takes ~250 of it. An 80pt icon
    /// block plus a pinned 70pt button left the form itself with nothing, so in compact height both
    /// move out of the vertical flow: the icon into a form row, the save action into the toolbar
    /// (which stays above the keyboard).
    @Environment(\.verticalSizeClass) private var vSizeClass
    private var compactHeight: Bool { vSizeClass == .compact }

    @State private var name: String
    @State private var targetAmountText: String
    @State private var deadline: Date
    @State private var includeDeadline: Bool
    @State private var selectedIcon: String
    @State private var selectedToken: String
    @State private var showIconPicker = false
    @FocusState private var focusedField: Field?

    private enum Field: CaseIterable, Hashable {
        case name
        case amount
    }

    private static func amountFormatter(for currencyCode: String) -> NumberFormatter {
        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .currency
        currencyFormatter.currencyCode = currencyCode

        let f = NumberFormatter()
        f.locale = .current
        f.numberStyle = .decimal
        f.minimumFractionDigits = currencyFormatter.minimumFractionDigits
        f.maximumFractionDigits = currencyFormatter.maximumFractionDigits
        return f
    }

    private static func editingFormatter(for currencyCode: String) -> NumberFormatter {
        let f = amountFormatter(for: currencyCode)
        f.groupingSeparator = ""
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 0
        return f
    }

    private var amountFormatter: NumberFormatter { Self.amountFormatter(for: currencyCode) }
    private var editingAmountFormatter: NumberFormatter { Self.editingFormatter(for: currencyCode) }
    private var maximumFractionDigits: Int { amountFormatter.maximumFractionDigits }
    private var amountPlaceholder: String { amountFormatter.string(for: 0) ?? "0" }

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol ?? currencyCode
    }

    private var parsedAmount: Decimal? {
        AmountParser.parse(targetAmountText)
    }

    /// User edits are sanitized at the binding boundary. Programmatic updates
    /// (the localized grouped display value on focus loss) write directly to
    /// `targetAmountText`, so their grouping separator is never mistaken for
    /// another decimal key.
    private var targetAmountBinding: Binding<String> {
        Binding(
            get: { targetAmountText },
            set: { newValue in
                targetAmountText = AmountParser.sanitizedInput(
                    newValue,
                    maximumFractionDigits: maximumFractionDigits
                )
            }
        )
    }

    private let initialGoalInput: GoalInput?
    private let onSave: (GoalInput) -> Void

    init(initialGoalInput: GoalInput? = nil, onSave: @escaping (GoalInput) -> Void) {
        self.initialGoalInput = initialGoalInput
        self.onSave = onSave
        _name = State(initialValue: initialGoalInput?.name ?? "")
        let currencyCode = UserDefaults.standard.string(forKey: "app_base_currency") ?? "EUR"
        _targetAmountText = State(initialValue: initialGoalInput.map {
            AddGoalSheet.amountFormatter(for: currencyCode).string(for: $0.targetAmount as NSDecimalNumber) ?? "\($0.targetAmount)"
        } ?? "")
        _deadline = State(initialValue: initialGoalInput?.deadline ?? Calendar.current.date(byAdding: .month, value: 6, to: Date())!)
        _includeDeadline = State(initialValue: initialGoalInput?.deadline != nil)
        _selectedIcon = State(initialValue: initialGoalInput?.iconName ?? GoalIcon.other.rawValue)
        _selectedToken = State(initialValue: initialGoalInput?.colorToken ?? "categoryIndigo")
    }

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount != nil }

    var body: some View {
        VStack(spacing: 24) {
            if !compactHeight {
                iconButton(size: 80, glyph: 36, corner: 20)
            }

            Form {
                Section("Details") {
                    if compactHeight {
                        HStack {
                            Text("Icon")
                                .foregroundStyle(.textMid)
                            Spacer()
                            iconButton(size: 44, glyph: 22, corner: 12)
                        }
                    }
                    TextField("Goal name", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .amount }
                        .onChange(of: name) { _, new in
                            if new.count > 24 { name = String(new.prefix(24)) }
                        }
                    HStack {
                        Spacer()
                        Text("\(name.count)/24")
                            .font(.caption)
                            .foregroundStyle(name.count >= 24 ? Color.negative : .textDim)
                    }
                }
                .appFormSectionBackground()

                Section("Target") {
                    HStack(spacing: 4) {
                        Text("Amount")
                            .foregroundStyle(.textMid)
                        TextField(amountPlaceholder, text: targetAmountBinding)
                            .textFieldStyle(.plain)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.textPrimary)
                            .monospacedDigit()
                            .frame(width: 200)
                            .focused($focusedField, equals: .amount)
                            .onChange(of: focusedField) { _, field in
                                let isFocused = field == .amount
                                if isFocused, let value = parsedAmount {
                                    targetAmountText = editingAmountFormatter.string(for: value as NSDecimalNumber) ?? targetAmountText
                                } else if let value = parsedAmount, !targetAmountText.isEmpty {
                                    targetAmountText = amountFormatter.string(for: value as NSDecimalNumber) ?? targetAmountText
                                }
                            }
                        Text(currencySymbol)
                            .foregroundStyle(.textMid)
                    }
                }
                .appFormSectionBackground()

                Section("Color") {
                    ColorTokenPicker(selectedToken: $selectedToken)
                        .padding(.vertical, 4)
                }
                .appFormSectionBackground()

                Section {
                    Toggle("Set a deadline", isOn: $includeDeadline)
                        .tint(.accentIndigo)
                    if includeDeadline {
                        DatePicker("Deadline", selection: $deadline, in: Date()..., displayedComponents: .date)
                            .tint(.accentIndigo)
                    }
                }
                .appFormSectionBackground()
            }
            .appFormBackground()
            .keyboardFieldNavigation($focusedField, order: Field.allCases)

            if !compactHeight {
                Button(action: save) {
                    Text(initialGoalInput == nil ? "Add Goal" : "Update Goal")
                        .font(.headline)
                        .foregroundStyle(isValid ? .primaryActionForeground : .textMid)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .glassEffect(.regular.tint(isValid ? Color.accentIndigo : Color.gray).interactive())
                }
                .disabled(!isValid)
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .sheet(isPresented: $showIconPicker) {
            GoalIconPickerSheet(selectedIcon: $selectedIcon)
                // .height(280) is taller than a landscape iPhone, so the picker opened clipped with
                // its own grid unreachable.
                .presentationDetents(compactHeight ? [.large] : [.height(280)])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedIcon) { old, new in
            let oldLabel = GoalIcon(rawValue: old)?.label ?? ""
            if name.trimmingCharacters(in: .whitespaces).isEmpty || name == oldLabel {
                name = GoalIcon(rawValue: new)?.label ?? ""
            }
        }
        .navigationTitle(initialGoalInput == nil ? "New Goal" : "Edit Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            if compactHeight {
                ToolbarItem(placement: .confirmationAction) {
                    Button(initialGoalInput == nil ? "Add Goal" : "Update Goal", action: save)
                        .bold()
                        .disabled(!isValid)
                }
            }
        }
    }

    private func iconButton(size: CGFloat, glyph: CGFloat, corner: CGFloat) -> some View {
        Button { showIconPicker = true } label: {
            let tokenColor = Color(selectedToken)
            Image(systemName: selectedIcon)
                .font(.system(size: glyph))
                .foregroundStyle(tokenColor)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: corner)
                        .fill(tokenColor.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner)
                        .strokeBorder(tokenColor.opacity(0.4), lineWidth: 1.5)
                )
        }
        .accessibilityLabel("Choose Icon")
    }

    private func save() {
        let target = parsedAmount ?? 0
        let dl: Date? = includeDeadline ? deadline : nil
        onSave(GoalInput(name: name, targetAmount: target, deadline: dl, colorToken: selectedToken, iconName: selectedIcon))
        dismiss()
    }
}

private struct GoalIconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Icon")
                .font(.headline)
                .padding(.top, 20)

            // Scrollable: the grid is taller than the sheet in landscape, and a clipped grid gives
            // no hint that there are more icons below.
            ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(GoalIcon.allCases, id: \.rawValue) { icon in
                    Button {
                        selectedIcon = icon.rawValue
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: icon.rawValue)
                                .font(.system(size: 28))
                                .foregroundStyle(selectedIcon == icon.rawValue ? Color.accentIndigo : .textMid)
                                .frame(width: 60, height: 60)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(selectedIcon == icon.rawValue
                                              ? Color.accentIndigo.opacity(0.15)
                                              : Color(.systemGray6))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(selectedIcon == icon.rawValue
                                                      ? Color.accentIndigo.opacity(0.4)
                                                      : Color.clear, lineWidth: 1.5)
                                )
                            Text(icon.label)
                                .font(.caption)
                                .foregroundStyle(.textMid)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            }
        }
    }
}
