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
                    }
                    HStack {
                        Text("Max (€)")
                        Spacer()
                        TextField("Any", text: $maxText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Absolute value range")
                }
            }
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
            }
            .onAppear {
                if let min = vm.filters.amountMin { minText = "\(min)" }
                if let max = vm.filters.amountMax { maxText = "\(max)" }
            }
        }
    }

    // ponytail: comma→period for European locale decimal input
    private var parsedMin: Decimal? {
        Decimal(string: minText.replacingOccurrences(of: ",", with: "."))
    }

    private var parsedMax: Decimal? {
        Decimal(string: maxText.replacingOccurrences(of: ",", with: "."))
    }

    private var isInvalidRange: Bool {
        if let min = parsedMin, let max = parsedMax { return min > max }
        return false
    }
}
