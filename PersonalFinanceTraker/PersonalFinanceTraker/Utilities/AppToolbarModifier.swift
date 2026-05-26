//
//  AppToolbarModifier.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct AppToolbarModifier: ViewModifier {
    @EnvironmentObject private var profileViewModel: ProfileViewModel
    @Binding var showingAddItemView: Bool
    @State private var showingProfile = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Open profile", systemImage: "gear") {
                        showingProfile = true
                    }
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add transaction", systemImage: "plus") {
                        showingAddItemView = true
                    }
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                }
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView(viewModel: profileViewModel)
                    .presentationDetents([.medium, .large])
                    .presentationBackground { AppBackground() }
            }
    }
}

extension View {
    func appToolbar(showingAddItemView: Binding<Bool>) -> some View {
        modifier(AppToolbarModifier(showingAddItemView: showingAddItemView))
    }
}
