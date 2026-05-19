//
//  AuthenticationWrapper.swift
//  PersonalFinanceTraker
//
//  Created by Gemini CLI on 26/02/26.
//

import SwiftUI
import SwiftData

struct AuthenticationWrapper: View {
    @StateObject private var authService = BiometricAuthService()
    @Environment(\.scenePhase) private var scenePhase
    
    let context: ModelContext
    
    var body: some View {
        Group {
            if authService.isUnlocked {
                MainTabView(context: context)
            } else {
                LockView {
                    authService.authenticate { _ in }
                }
            }
        }
        .onAppear {
            authService.authenticate { _ in }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active && !authService.isUnlocked {
                authService.authenticate { _ in }
            } else if newPhase == .background {
                authService.lock()
            }
        }
    }
}
