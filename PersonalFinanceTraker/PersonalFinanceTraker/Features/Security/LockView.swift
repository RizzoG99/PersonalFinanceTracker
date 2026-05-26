//
//  LockView.swift
//  PersonalFinanceTraker
//
//  Created by Gemini CLI on 26/02/26.
//

import SwiftUI
import LocalAuthentication

struct LockView: View {
    let authenticate: () -> Void

    private var biometryType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    private var biometryIcon: String {
        biometryType == .touchID ? "touchid" : "faceid"
    }

    private var biometryLabel: String {
        switch biometryType {
        case .touchID: return "Unlock with Touch ID"
        case .faceID: return "Unlock with Face ID"
        default:       return "Unlock"
        }
    }

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // App Icon / Logo Placeholder
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.accentIndigo)
                
                Text("Personal Finance Tracker")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.textPrimary)
            }
            
            Text("Your financial data is protected.")
                .font(.subheadline)
                .foregroundStyle(.textMid)
            
            Spacer()
            
            Button(action: authenticate) {
                HStack {
                    Image(systemName: biometryIcon)
                    Text(biometryLabel)
                }
                .font(.headline)
                .foregroundStyle(.textPrimary)
                .padding()
                .frame(maxWidth: .infinity)
                .glassEffect(.regular.tint(Color.accentIndigo).interactive())
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .appBackground()
    }
}

#Preview {
    LockView(authenticate: {})
}
