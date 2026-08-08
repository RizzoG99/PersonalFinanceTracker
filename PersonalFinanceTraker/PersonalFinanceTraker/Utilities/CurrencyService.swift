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

extension Decimal {
    // Device locale governs grouping/decimal separators; symbol lookup is pinned to a fixed
    // locale so e.g. USD always renders "$" instead of the device region's CLDR choice of
    // showing the ISO code for "foreign" currencies (observed with device region IT).
    private static func stableCurrencySymbol(for currencyCode: String) -> String {
        let probe = NumberFormatter()
        probe.locale = Locale(identifier: "en_US")
        probe.numberStyle = .currency
        probe.currencyCode = currencyCode
        return probe.currencySymbol ?? currencyCode
    }

    public func formattedEUR(currency: String? = nil) -> String {
        // ponytail: name says EUR but formats base currency; rename in a follow-up
        let baseCurrency = currency ?? UserDefaults.standard.string(forKey: "app_base_currency") ?? "EUR"
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = baseCurrency
        fmt.currencySymbol = Self.stableCurrencySymbol(for: baseCurrency)
        return fmt.string(from: self as NSDecimalNumber) ?? "\(fmt.currencySymbol ?? "€")0.00"
    }

    public func formattedEURCompact(currency: String? = nil) -> String {
        // ponytail: name says EUR but formats base currency; rename in a follow-up
        let baseCurrency = currency ?? UserDefaults.standard.string(forKey: "app_base_currency") ?? "EUR"
        let double = Double(truncating: self as NSDecimalNumber)
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = baseCurrency
        fmt.maximumFractionDigits = 1
        fmt.minimumFractionDigits = 0
        let currencySymbol = Self.stableCurrencySymbol(for: baseCurrency)
        switch abs(double) {
        case 1_000_000...:
            fmt.positiveSuffix = "M \(currencySymbol)"
            fmt.negativeSuffix = "M \(currencySymbol)"
            fmt.currencySymbol = ""
            return fmt.string(from: NSNumber(value: double / 1_000_000)) ?? self.formattedEUR(currency: baseCurrency)
        case 1_000...:
            fmt.positiveSuffix = "K \(currencySymbol)"
            fmt.negativeSuffix = "K \(currencySymbol)"
            fmt.currencySymbol = ""
            return fmt.string(from: NSNumber(value: double / 1_000)) ?? self.formattedEUR(currency: baseCurrency)
        default:
            return self.formattedEUR(currency: baseCurrency)
        }
    }
}
