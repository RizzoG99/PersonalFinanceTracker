//
//  AppToolbarModifier.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct AppToolbarModifier: ViewModifier {
    @EnvironmentObject private var profileViewModel: ProfileViewModel
    @Binding var showingAddItemView: Bool
    @State private var showingProfile = false
    @State private var selectedDetent: PresentationDetent = .large

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Open profile", systemImage: "gear") {
                        selectedDetent = .large
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
                ProfileView(viewModel: profileViewModel, selectedDetent: $selectedDetent)
                    .presentationDetents([.medium, .large], selection: $selectedDetent)
                    .presentationBackground { AppBackground() }
            }
    }
}

extension View {
    func appToolbar(showingAddItemView: Binding<Bool>) -> some View {
        modifier(AppToolbarModifier(showingAddItemView: showingAddItemView))
    }
}
