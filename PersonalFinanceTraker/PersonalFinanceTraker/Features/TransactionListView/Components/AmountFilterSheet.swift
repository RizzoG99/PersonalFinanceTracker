//
//  AmountFilterSheet.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct AmountFilterSheet: View {
    @Environment(TransactionListViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @State private var minText = ""
    @State private var maxText = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Min (€)")
                        Spacer()
                        TextField("Any", text: $minText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($fieldFocused)
                    }
                    HStack {
                        Text("Max (€)")
                        Spacer()
                        TextField("Any", text: $maxText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($fieldFocused)
                    }
                } header: {
                    Text("Amount range")
                }
                .appFormSectionBackground()
            }
            .appFormBackground()
            .navigationTitle("Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        vm.filters.amountMin = parsedMin
                        vm.filters.amountMax = parsedMax
                        dismiss()
                    }
                    .disabled(isInvalidRange)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // decimalPad has no return key — give users a way to dismiss it.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
            .onAppear {
                if let min = vm.filters.amountMin { minText = AmountParser.editingText(min) }
                if let max = vm.filters.amountMax { maxText = AmountParser.editingText(max) }
            }
        }
    }

    private var parsedMin: Decimal? {
        AmountParser.parse(minText)
    }

    private var parsedMax: Decimal? {
        AmountParser.parse(maxText)
    }

    private var isInvalidRange: Bool {
        if let min = parsedMin, let max = parsedMax { return min > max }
        return false
    }
}
