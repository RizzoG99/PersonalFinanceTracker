//
//  LockView.swift
//  PersonalFinanceTraker
//
//  Created by Gemini CLI on 26/02/26.
//

import SwiftUI

struct LockView: View {
    let authenticate: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // App Icon / Logo Placeholder
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
                
                Text("Personal Finance Tracker")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Text("Your financial data is protected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button(action: authenticate) {
                HStack {
                    Image(systemName: "faceid")
                    Text("Unlock with FaceID / TouchID")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
