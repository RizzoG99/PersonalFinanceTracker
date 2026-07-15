//
//  CurrencyService.swift
//  PersonalFinanceTraker
//
//  Created by Gemini CLI on 26/02/26.
//

import Foundation

/// Service for managing multi-currency support and conversion
public class CurrencyService: ObservableObject {
    
    @Published public var baseCurrency: String = "EUR"
    
    // Default supported currencies
    public let supportedCurrencies = ["EUR", "USD", "GBP", "JPY", "AUD", "CAD", "CHF", "CNY"]
    
    // Static conversion rates (mocked for now)
    private let rates: [String: Decimal] = [
        "EUR": 1.0,
        "USD": 1.08,
        "GBP": 0.85,
        "JPY": 162.0,
        "AUD": 1.65,
        "CAD": 1.47,
        "CHF": 0.95,
        "CNY": 7.8
    ]
    
    private let kBaseCurrencyKey = "app_base_currency"
    
    public init() {
        self.baseCurrency = UserDefaults.standard.string(forKey: kBaseCurrencyKey) ?? "EUR"
    }
    
    public func setBaseCurrency(_ code: String) {
        baseCurrency = code
        UserDefaults.standard.set(code, forKey: kBaseCurrencyKey)
    }
    
    /// Converts an amount from one currency to another
    public func convert(_ amount: Decimal, from source: String, to target: String) -> Decimal {
        guard let sourceRate = rates[source], let targetRate = rates[target] else {
            return amount
        }
        
        // Convert to intermediate (EUR base) then to target
        let amountInBase = amount / sourceRate
        return amountInBase * targetRate
    }
    
    /// Converts an amount to the app's base currency
    public func convertToBase(_ amount: Decimal, from source: String) -> Decimal {
        return convert(amount, from: source, to: baseCurrency)
    }
    
    /// Returns a currency formatter for a specific currency code
    public func formatter(for currencyCode: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
    
    /// Returns the currency symbol for a code
    public func symbol(for currencyCode: String) -> String {
        return Locale.current.localizedString(forCurrencyCode: currencyCode) ?? currencyCode
    }
}

extension Decimal {
    public func formattedEUR() -> String {
        // ponytail: name says EUR but formats base currency; rename in a follow-up
        let baseCurrency = UserDefaults.standard.string(forKey: "app_base_currency") ?? "EUR"
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = baseCurrency
        let fallbackSymbol = Locale.current.localizedString(forCurrencyCode: baseCurrency) ?? "€"
        return fmt.string(from: self as NSDecimalNumber) ?? "\(fallbackSymbol)0.00"
    }

    public func formattedEURCompact() -> String {
        // ponytail: name says EUR but formats base currency; rename in a follow-up
        let baseCurrency = UserDefaults.standard.string(forKey: "app_base_currency") ?? "EUR"
        let double = Double(truncating: self as NSDecimalNumber)
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = baseCurrency
        fmt.maximumFractionDigits = 1
        fmt.minimumFractionDigits = 0
        let currencySymbol = fmt.currencySymbol ?? Locale.current.localizedString(forCurrencyCode: baseCurrency) ?? "€"
        switch abs(double) {
        case 1_000_000...:
            fmt.positiveSuffix = "M \(currencySymbol)"
            fmt.negativeSuffix = "M \(currencySymbol)"
            fmt.currencySymbol = ""
            return fmt.string(from: NSNumber(value: double / 1_000_000)) ?? self.formattedEUR()
        case 1_000...:
            fmt.positiveSuffix = "K \(currencySymbol)"
            fmt.negativeSuffix = "K \(currencySymbol)"
            fmt.currencySymbol = ""
            return fmt.string(from: NSNumber(value: double / 1_000)) ?? self.formattedEUR()
        default:
            return self.formattedEUR()
        }
    }
}
