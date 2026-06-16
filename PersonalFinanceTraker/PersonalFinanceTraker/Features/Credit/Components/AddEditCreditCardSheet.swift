//
//  AddEditCreditCardSheet.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct AddEditCreditCardSheet: View {
    var viewModel: CreditViewModel
    var cardToEdit: CreditCardModel?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var lastFour: String = ""
    @State private var balanceText: String = ""
    @State private var limitText: String = ""
    @State private var selectedColorName: String = "accentIndigo"

    private let availableColors: [(name: String, color: Color)] = [
        ("accentIndigo", .accentIndigo),
        ("positive", .positive),
        ("categoryTeal", .categoryTeal),
        ("categoryPink", .categoryPink),
        ("categoryAmber", .categoryAmber),
        ("categoryPurple", .categoryPurple),
    ]

    var isEditing: Bool { cardToEdit != nil }

    var isValid: Bool {
        !name.isEmpty &&
        lastFour.count == 4 &&
        Decimal(string: balanceText) != nil &&
        Decimal(string: limitText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card Details") {
                    TextField("Card name", text: $name)
                        .listRowBackground(Color.formRow)
                    TextField("Last 4 digits", text: $lastFour)
                        .keyboardType(.numberPad)
                        .onChange(of: lastFour) { _, new in
                            lastFour = String(new.filter(\.isNumber).prefix(4))
                        }
                        .listRowBackground(Color.formRow)
                }
                .foregroundStyle(.textPrimary)

                Section("Balance & Limit") {
                    HStack {
                        Text("Balance")
                            .foregroundStyle(.textMid)
                        Spacer()
                        TextField("0.00", text: $balanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.textPrimary)
                    }
                    .listRowBackground(Color.formRow)
                    HStack {
                        Text("Credit Limit")
                            .foregroundStyle(.textMid)
                        Spacer()
                        TextField("0.00", text: $limitText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.textPrimary)
                    }
                    .listRowBackground(Color.formRow)
                }

                Section("Card Color") {
                    HStack(spacing: 16) {
                        ForEach(availableColors, id: \.name) { entry in
                            Circle()
                                .fill(entry.color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if selectedColorName == entry.name {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { selectedColorName = entry.name }
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.formRow)
                }
            }
            .appFormBackground()
            .appBackground()
            .navigationTitle(isEditing ? "Edit Card" : "Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(isValid ? .accentIndigo : .textDim)
                        .disabled(!isValid)
                }
            }
        }
        .onAppear {
            if let card = cardToEdit {
                name = card.name
                lastFour = card.lastFour
                balanceText = "\(card.balance)"
                limitText = "\(card.limit)"
                selectedColorName = card.colorName
            }
        }
    }

    private func save() {
        guard let balance = Decimal(string: balanceText),
              let limit = Decimal(string: limitText) else { return }

        if let card = cardToEdit {
            card.name = name
            card.lastFour = lastFour
            card.balance = balance
            card.limit = limit
            card.colorName = selectedColorName
            viewModel.saveCardEdits()
        } else {
            let card = CreditCardModel(
                name: name,
                lastFour: lastFour,
                balance: balance,
                limit: limit,
                colorName: selectedColorName
            )
            viewModel.addCard(card)
        }
        dismiss()
    }
}
