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
    private let defaults: UserDefaults

    /// Injectable so tests don't race on shared UserDefaults across parallel suites
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.baseCurrency = defaults.string(forKey: kBaseCurrencyKey) ?? "EUR"
    }

    public func setBaseCurrency(_ code: String) {
        baseCurrency = code
        defaults.set(code, forKey: kBaseCurrencyKey)
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
