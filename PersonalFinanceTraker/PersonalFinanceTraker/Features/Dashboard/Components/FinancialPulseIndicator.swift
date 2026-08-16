//
//  FinancialPulseIndicator.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct FinancialPulseIndicator: View {
    let state: DailyCheckInState

    var body: some View {
        Image(systemName: symbolName)
            .font(.title3)
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.12), in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(tint.opacity(0.28), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch state {
        case .pending:
            "circle.dotted.circle"
        case .transactionLogged:
            "checkmark.circle.fill"
        case .noSpendConfirmed:
            "checkmark.seal.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .pending:
            .accentIndigo
        case .transactionLogged, .noSpendConfirmed:
            .positive
        }
    }
}
