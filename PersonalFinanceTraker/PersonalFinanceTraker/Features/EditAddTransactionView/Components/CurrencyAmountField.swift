//
//  CurrencyAmountField.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI

struct CurrencyAmountField: View {
    @Binding var amount: Double
    @Binding var currencyCode: String
    @FocusState private var isFocused: Bool
    @State private var displayText: String = ""
    
    let label: String
    let placeholder: String
    
    // Currency formatter for display
    private var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currencyAccounting
        formatter.currencyCode = currencyCode
        formatter.decimalSeparator = ","
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
    
    init(
        label: String = "Amount",
        placeholder: String = "0",
        amount: Binding<Double>,
        currencyCode: Binding<String>
    ) {
        self.label = label
        self.placeholder = placeholder
        self._amount = amount
        self._currencyCode = currencyCode
    }
    
    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol ?? currencyCode
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(currencySymbol)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: $displayText)
                    .textFieldStyle(.plain)
                    .keyboardType(.decimalPad)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .font(.system(size: 44))
                    .fontWeight(.heavy)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .onChange(of: isFocused) { _, newValue in
                        if newValue {
                            if amount > 0 {
                                displayText = formatNumberForEditing(amount)
                            } else {
                                displayText = ""
                            }
                        } else {
                            parseAndFormatAmount()
                        }
                    }
                    .onAppear {
                        updateDisplayText()
                    }
                    .onChange(of: amount) { _, _ in
                        if !isFocused {
                            updateDisplayText()
                        }
                    }
                    .onChange(of: currencyCode) { _, _ in
                        if !isFocused {
                            updateDisplayText()
                        }
                    }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func formatNumberForEditing(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = Locale.current.decimalSeparator ?? ","
        formatter.groupingSeparator = ""
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
    
    private func parseAndFormatAmount() {
        // Parse the text field input
        let cleanText = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanText.isEmpty {
            amount = 0.0
            displayText = ""
            return
        }
        
        // Replace dots with commas if using comma as decimal separator
        let normalizedText = cleanText.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ",")
        
        // Try to parse the number
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = Locale.current.decimalSeparator ?? ","
        
        if let parsedValue = formatter.number(from: normalizedText)?.doubleValue, parsedValue >= 0 {
            amount = parsedValue
            // Format the display text with currency
            displayText = currencyFormatter.string(from: NSNumber(value: amount)) ?? ""
        } else {
            // Invalid input, reset to previous valid value or zero
            if amount > 0 {
                displayText = currencyFormatter.string(from: NSNumber(value: amount)) ?? ""
            } else {
                amount = 0.0
                displayText = ""
            }
        }
    }
    
    private func updateDisplayText() {
        if amount > 0 {
            displayText = currencyFormatter.string(from: NSNumber(value: amount)) ?? ""
        } else {
            displayText = ""
        }
    }
}

// MARK: - Focus Control Extension

extension CurrencyAmountField {
    /// Programmatically focus the amount field
    func focused(_ isFocused: Bool) -> some View {
        self.onAppear {
            self.isFocused = isFocused
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var amount: Double = 0.0
        @State private var currency: String = "EUR"
        
        var body: some View {
            VStack(spacing: 20) {
                CurrencyAmountField(
                    label: "Amount",
                    placeholder: "0",
                    amount: $amount,
                    currencyCode: $currency
                )
                
                Text("Current amount: \(amount, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button("Set to 123.45") {
                    amount = 123.45
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}
