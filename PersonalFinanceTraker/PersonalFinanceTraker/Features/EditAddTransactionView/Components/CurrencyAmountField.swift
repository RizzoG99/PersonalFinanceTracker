//
//  CurrencyAmountField.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI

struct CurrencyAmountField: View {
    // Optional so previews/hosts without AppSettings render unblurred instead of crashing.
    @Environment(AppSettings.self) private var settings: AppSettings?
    @Binding var amount: Double
    @Binding var currencyCode: String
    @FocusState private var isFocused: Bool
    @State private var displayText: String = ""

    /// Parent-owned focus, so a form can chain Amount → Name from the keyboard bar. This field uses
    /// a decimalPad, which has no Return key, so without an external handle on its focus there is no
    /// way off it except dismissing the keyboard. nil keeps the old self-managed behaviour, which is
    /// all the bulk-edit sheet and the previews need.
    var focus: FocusState<TransactionFormField?>.Binding?

    /// True whichever way focus is being tracked.
    private var hasFocus: Bool {
        if let focus { return focus.wrappedValue == .amount }
        return isFocused
    }

    // Privacy mode blurs the amount, but only until the user taps in to edit it.
    private var isAmountHidden: Bool { (settings?.hideAmounts ?? false) && !hasFocus }

    let label: String
    let placeholder: String
    let shouldAutoFocus: Bool
    let focusTrigger: Int

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
        currencyCode: Binding<String>,
        shouldAutoFocus: Bool = false,
        focusTrigger: Int = 0,
        focus: FocusState<TransactionFormField?>.Binding? = nil
    ) {
        self.label = label
        self.placeholder = placeholder
        self._amount = amount
        self._currencyCode = currencyCode
        self.shouldAutoFocus = shouldAutoFocus
        self.focusTrigger = focusTrigger
        self.focus = focus
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

                amountField
            }
            .blur(radius: isAmountHidden ? 16 : 0)
            .accessibilityValue(isAmountHidden ? String(localized: "Amount hidden") : displayText)
            .animation(.easeInOut(duration: 0.25), value: isAmountHidden)
        }
    }

    @ViewBuilder
    private var amountField: some View {
        // One field, two ways to bind focus: the parent's shared enum when it wants to chain fields,
        // otherwise the local Bool.
        if let focus {
            styledField.focused(focus, equals: .amount)
        } else {
            styledField.focused($isFocused)
        }
    }

    private var styledField: some View {
        TextField(placeholder, text: $displayText)
                    .textFieldStyle(.plain)
                    .keyboardType(.decimalPad)
                    .submitLabel(.done)
                    .font(.system(size: 44))
                    .fontWeight(.heavy)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .onChange(of: hasFocus) { _, newValue in
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
                    .onChange(of: displayText) { _, newValue in
                        guard hasFocus else { return }
                        let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if clean.isEmpty {
                            amount = 0.0
                            return
                        }
                        let normalized = clean.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ",")
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.decimalSeparator = Locale.current.decimalSeparator ?? ","
                        if let parsed = formatter.number(from: normalized)?.doubleValue, parsed >= 0 {
                            amount = parsed
                        }
                    }
                    .onAppear {
                        updateDisplayText()
                        if shouldAutoFocus {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                setFocus(true)
                            }
                        }
                    }
                    .onChange(of: focusTrigger) { _, _ in
                        // Clear the stale display up front: resetForm() set amount = 0 while
                        // the field was focused, so onChange(of: amount) bailed on its
                        // !isFocused guard and displayText still shows the old number. Without
                        // this, the false -> true focus cycle below runs parseAndFormatAmount()
                        // on that stale text and restores the old amount. Clearing first makes
                        // that parse see empty text and keep amount at 0.
                        displayText = ""
                        setFocus(false)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            setFocus(true)
                        }
                    }
                    .onChange(of: amount) { _, _ in
                        if !hasFocus {
                            updateDisplayText()
                        }
                    }
                    .onChange(of: currencyCode) { _, _ in
                        if !hasFocus {
                            updateDisplayText()
                        }
                    }
    }

    // MARK: - Private Methods

    private func setFocus(_ on: Bool) {
        if let focus {
            focus.wrappedValue = on ? .amount : nil
        } else {
            isFocused = on
        }
    }
    
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
                    currencyCode: $currency,
                    shouldAutoFocus: true
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
