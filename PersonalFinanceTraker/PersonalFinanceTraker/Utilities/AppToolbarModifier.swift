//
//  AppToolbarModifier.swift
//  PersonalFinanceTraker
//

import SwiftUI
import UIKit

struct AppToolbarModifier: ViewModifier {
    @Environment(ProfileViewModel.self) private var profileViewModel: ProfileViewModel
    @Environment(TransactionListViewModel.self) private var transactionViewModel: TransactionListViewModel
    @Environment(DataChangedSignal.self) private var dataChanged: DataChangedSignal
    @Binding var showingAddItemView: Bool
    /// When false, the gear/＋ items are hidden (e.g. while the Activity list is in
    /// multi-select mode and shows its own Cancel / count / Select All toolbar instead).
    var enabled: Bool = true
    @State private var showingProfile = false
    @State private var selectedDetent: PresentationDetent = .large

    /// The iPad shell owns these actions itself — Settings is a sidebar destination and Add
    /// lives in the shell's toolbar — so showing them again per screen would duplicate both.
    /// The sheets below still apply: ProfileView can trigger the import flow from anywhere.
    private var showsItems: Bool {
        enabled && UIDevice.current.userInterfaceIdiom != .pad
    }

    func body(content: Content) -> some View {
        @Bindable var transactionViewModel = transactionViewModel
        return content
            .toolbar {
                if showsItems {
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
                        .foregroundStyle(.primaryActionForeground)
                        .glassEffect(.regular.tint(Color.accentIndigo).interactive())
                    }
                }
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView(viewModel: profileViewModel, selectedDetent: $selectedDetent)
                    .environment(dataChanged)
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
    func appToolbar(showingAddItemView: Binding<Bool>, enabled: Bool = true) -> some View {
        modifier(AppToolbarModifier(showingAddItemView: showingAddItemView, enabled: enabled))
    }
}
