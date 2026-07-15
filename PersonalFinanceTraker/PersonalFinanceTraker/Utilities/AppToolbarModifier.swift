//
//  AppToolbarModifier.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct AppToolbarModifier: ViewModifier {
    @Environment(ProfileViewModel.self) private var profileViewModel: ProfileViewModel
    @Environment(TransactionListViewModel.self) private var transactionViewModel: TransactionListViewModel
    @Binding var showingAddItemView: Bool
    @State private var showingProfile = false
    @State private var selectedDetent: PresentationDetent = .large

    func body(content: Content) -> some View {
        @Bindable var transactionViewModel = transactionViewModel
        return content
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
            // ImportFlowView is at the same level as ProfileView so there's
            // never more than one sheet on screen at a time
            .sheet(isPresented: $transactionViewModel.showingImportFlow) {
                ImportFlowView(viewModel: transactionViewModel)
            }
            .onChange(of: transactionViewModel.showingImportFlow) { _, isShowing in
                if isShowing { showingProfile = false }
            }
            .alert(
                "Import",
                isPresented: Binding(
                    get: { transactionViewModel.importError != nil },
                    set: { if !$0 { transactionViewModel.importError = nil } }
                )
            ) {
                Button("OK") { transactionViewModel.importError = nil }
            } message: {
                Text(transactionViewModel.importError ?? "")
            }
    }
}

extension View {
    func appToolbar(showingAddItemView: Binding<Bool>) -> some View {
        modifier(AppToolbarModifier(showingAddItemView: showingAddItemView))
    }
}
