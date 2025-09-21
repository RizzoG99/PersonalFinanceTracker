//
//  CurrencyAmountField.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI

struct CurrencyAmountField: View {
    @Binding var amount: Double
    @FocusState private var isFocused: Bool
    @State private var displayText: String = ""
    
    let label: String
    let placeholder: String
    
    // Currency formatter for display
    private var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currencyAccounting
        formatter.currencyCode = Locale.current.currency?.identifier ?? "EUR"
        formatter.decimalSeparator = ","
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
    
    init(
        label: String = "Amount",
        placeholder: String = "0",
        amount: Binding<Double>
    ) {
        self.label = label
        self.placeholder = placeholder
        self._amount = amount
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                // Currency symbol
                Text(currencyFormatter.currencySymbol ?? "€")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
                TextField(placeholder, text: $displayText)
                    .textFieldStyle(.plain)
                    .keyboardType(.decimalPad)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                    .foregroundStyle(.primary)
                    .onChange(of: isFocused) { oldValue, newValue in
                        if newValue {
                            // When field gains focus, show raw number for editing
                            if amount > 0 {
                                displayText = formatNumberForEditing(amount)
                            } else {
                                displayText = ""
                            }
                        } else {
                            // When field loses focus, parse and format
                            parseAndFormatAmount()
                        }
                    }
                    .onAppear {
                        // Initialize display text
                        updateDisplayText()
                    }
                    .onChange(of: amount) { oldValue, newValue in
                        // Update display text when amount changes externally
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
        
        var body: some View {
            VStack(spacing: 20) {
                CurrencyAmountField(
                    label: "Amount",
                    placeholder: "0",
                    amount: $amount
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
