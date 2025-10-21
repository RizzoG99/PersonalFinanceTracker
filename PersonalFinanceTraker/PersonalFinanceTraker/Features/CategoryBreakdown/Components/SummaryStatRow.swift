//
//  SummaryStatRow.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/10/25.
//

import SwiftUI


/// A row showing summary statistics
struct SummaryStatRow: View {
    let label: String
    let value: Any
    let currencyCode: String?
    let isNumber: Bool
    let isText: Bool
    
    init(label: String, value: Decimal, currencyCode: String) {
        self.label = label
        self.value = value
        self.currencyCode = currencyCode
        self.isNumber = false
        self.isText = false
    }
    
    init(label: String, value: String, isNumber: Bool = false, isText: Bool = false) {
        self.label = label
        self.value = value
        self.currencyCode = nil
        self.isNumber = isNumber
        self.isText = isText
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Group {
                if let currencyCode = currencyCode, let decimalValue = value as? Decimal {
                    Text(decimalValue, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } else if let stringValue = value as? String {
                    Text(stringValue)
                        .font(.subheadline)
                        .fontWeight(isNumber ? .semibold : .medium)
                }
            }
            .foregroundColor(.secondary)
        }
    }
}
