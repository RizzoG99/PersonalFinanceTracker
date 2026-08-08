//
//  DecimalFormatting.swift
//  PersonalFinanceTraker
//
//  Lives in Shared/ — an Xcode synced group compiled into both the app target
//  and SafeToSpendWidgetExtension.
//

import Foundation

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
