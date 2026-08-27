//
//  HideAmountsControl.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// Always-visible CTA for toggling `AppSettings.hideAmounts`, matching the eye icon on Home's
/// `BalanceCardView`. Shake-to-hide (`onShake`, wired via `hideAmountsShortcut`) previously was
/// the iPhone-only path to this; #52 asked for a discoverable control that doesn't depend on the
/// shake gesture working (it doesn't reach `IPadRootView` at all — no window override installs a
/// shake handler for that shell) or being comfortable on a device iPad-sized.
struct HideAmountsButton: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        Button {
            appSettings.toggleHideAmounts()
        } label: {
            Image(systemName: appSettings.hideAmounts ? "eye.slash" : "eye")
        }
        .accessibilityLabel(appSettings.hideAmounts ? String(localized: "Show amounts") : String(localized: "Hide amounts"))
    }
}

/// Shake-to-toggle plus the "Amounts hidden/shown" toast, lifted out of `MainTabView` so
/// `IPadRootView` can opt into the same behaviour (issue #52 — shake previously only worked on
/// the iPhone shell since `.onShake` was never attached to the iPad one).
private struct HideAmountsShortcut: ViewModifier {
    let appSettings: AppSettings
    @State private var showPrivacyToast = false
    @State private var privacyToastTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showPrivacyToast {
                    ToastBanner(
                        icon: appSettings.hideAmounts ? "eye.slash.fill" : "eye.fill",
                        message: appSettings.hideAmounts ? String(localized: "Amounts hidden") : String(localized: "Amounts shown")
                    ) { EmptyView() }
                        .accessibilityElement(children: .combine)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: showPrivacyToast)
            .onShake {
                appSettings.toggleHideAmounts()
            }
            .onChange(of: appSettings.hideAmounts) { _, _ in
                privacyToastTask?.cancel()
                showPrivacyToast = true
                privacyToastTask = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    if !Task.isCancelled { showPrivacyToast = false }
                }
            }
    }
}

extension View {
    func hideAmountsShortcut(_ appSettings: AppSettings) -> some View {
        modifier(HideAmountsShortcut(appSettings: appSettings))
    }
}
