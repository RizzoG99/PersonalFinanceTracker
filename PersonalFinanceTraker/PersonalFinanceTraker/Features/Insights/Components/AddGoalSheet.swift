//
//  AddGoalSheet.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct AddGoalSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var targetAmountText: String
    @State private var deadline: Date
    @State private var includeDeadline: Bool
    @State private var selectedIcon: String
    @State private var selectedToken: String
    @State private var showIconPicker = false
    @FocusState private var amountFocused: Bool

    private static let amountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private var parsedAmount: Decimal? {
        let parts = targetAmountText.replacingOccurrences(of: ",", with: "").components(separatedBy: ".")
        return Decimal(string: parts.count > 2 ? parts.joined() : parts.joined(separator: "."))
    }

    private let existingGoal: GoalModel?
    private let onSave: (GoalModel) -> Void

    init(goal: GoalModel? = nil, onSave: @escaping (GoalModel) -> Void) {
        self.existingGoal = goal
        self.onSave = onSave
        _name = State(initialValue: goal?.name ?? "")
        _targetAmountText = State(initialValue: goal.map {
            AddGoalSheet.amountFormatter.string(for: $0.targetAmount as NSDecimalNumber) ?? "\($0.targetAmount)"
        } ?? "")
        _deadline = State(initialValue: goal?.deadline ?? Calendar.current.date(byAdding: .month, value: 6, to: Date())!)
        _includeDeadline = State(initialValue: goal?.deadline != nil)
        _selectedIcon = State(initialValue: goal?.iconName ?? GoalIcon.other.rawValue)
        _selectedToken = State(initialValue: goal?.colorToken ?? "categoryIndigo")
    }

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount != nil }

    var body: some View {
        VStack(spacing: 24) {
            Button { showIconPicker = true } label: {
                let tokenColor = Color(selectedToken)
                Image(systemName: selectedIcon)
                    .font(.system(size: 36))
                    .foregroundStyle(tokenColor)
                    .frame(width: 80, height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(tokenColor.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(tokenColor.opacity(0.4), lineWidth: 1.5)
                    )
            }
            .sheet(isPresented: $showIconPicker) {
                GoalIconPickerSheet(selectedIcon: $selectedIcon)
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
            }

            Form {
                Section("Details") {
                    TextField("Goal name", text: $name)
                        .onChange(of: name) { _, new in
                            if new.count > 24 { name = String(new.prefix(24)) }
                        }
                    HStack {
                        Spacer()
                        Text("\(name.count)/24")
                            .font(.caption)
                            .foregroundStyle(name.count >= 24 ? .red : .textDim)
                    }
                }
                .appFormSectionBackground()

                Section("Target") {
                    HStack {
                        Text("Amount")
                            .foregroundStyle(.textMid)
                        Spacer()
                        TextField("0.00", text: $targetAmountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.textPrimary)
                            .frame(maxWidth: 120)
                            .focused($amountFocused)
                            .onChange(of: amountFocused) { _, isFocused in
                                if isFocused {
                                    targetAmountText = targetAmountText.replacingOccurrences(of: ",", with: "")
                                } else if let value = parsedAmount, !targetAmountText.isEmpty {
                                    targetAmountText = Self.amountFormatter.string(for: value as NSDecimalNumber) ?? targetAmountText
                                }
                            }
                        Text("€")
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

            Button(action: save) {
                Text(existingGoal == nil ? "Add Goal" : "Update Goal")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .glassEffect(.regular.tint(isValid ? Color.accentIndigo : Color.gray).interactive())
            }
            .disabled(!isValid)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onChange(of: selectedIcon) { old, new in
            let oldLabel = GoalIcon(rawValue: old)?.label ?? ""
            if name.trimmingCharacters(in: .whitespaces).isEmpty || name == oldLabel {
                name = GoalIcon(rawValue: new)?.label ?? ""
            }
        }
        .navigationTitle(existingGoal == nil ? "New Goal" : "Edit Goal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        let target = parsedAmount ?? 0
        let dl: Date? = includeDeadline ? deadline : nil

        if let existing = existingGoal {
            existing.name = name
            existing.targetAmount = target
            existing.deadline = dl
            existing.iconName = selectedIcon
            existing.colorToken = selectedToken
            onSave(existing)
        } else {
            onSave(GoalModel(name: name, targetAmount: target, deadline: dl, colorToken: selectedToken, iconName: selectedIcon))
        }
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
