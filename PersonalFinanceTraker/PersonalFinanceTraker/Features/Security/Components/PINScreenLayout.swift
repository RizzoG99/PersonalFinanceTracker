import SwiftUI

/// Shared chrome for the four PIN screens: mascot, title, dots, then whatever the step needs.
///
/// The three call sites had the same hand-rolled `VStack { Spacer; monkey; title; dots; pad }`,
/// which only ever fits a portrait viewport — 100pt of monkey plus 340pt of keypad plus 112pt of
/// padding needs ~600pt, and landscape gives ~370pt with no scroll view to rescue it, so the pad
/// was cut in half. Landscape puts the heading beside the content instead of above it, which is
/// what the system PIN screens do and what makes the numbers reachable at all.
struct PINScreenLayout<Content: View, Footer: View>: View {
    @Binding var eyesOpen: Bool
    var isShaking: Bool = false
    var isBouncing: Bool = false
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var errorMessage: String = ""
    /// nil hides the dots, for setup steps that aren't PIN entry.
    var filledCount: Int?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    @Environment(\.verticalSizeClass) private var vSizeClass
    private var compact: Bool { vSizeClass == .compact }

    var body: some View {
        // Same subviews, two arrangements — no duplicated hierarchy to keep in sync.
        let layout = compact
            ? AnyLayout(HStackLayout(spacing: 28))
            : AnyLayout(VStackLayout(spacing: 0))

        return layout {
            heading
            VStack(spacing: 0) {
                content
                footer
                    .padding(.top, compact ? 12 : 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, compact ? 20 : 24)
        .padding(.vertical, compact ? 12 : 0)
        .appBackground()
    }

    private var heading: some View {
        VStack(spacing: 0) {
            MonkeyAnimationView(
                eyesOpen: $eyesOpen,
                isShaking: isShaking,
                isBouncing: isBouncing,
                size: compact ? 56 : 100
            )
            .padding(.bottom, compact ? 12 : 32)

            VStack(spacing: 8) {
                Text(title)
                    .font(compact ? .title3.weight(.bold) : .title2.weight(.bold))
                    .foregroundStyle(.textPrimary)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.textDim)
                        .multilineTextAlignment(.center)
                }

                if !errorMessage.isEmpty {
                    // LocalizedStringKey because PINSetupView passes catalogue keys. The lockout
                    // messages the other two view models build are interpolated at runtime, so they
                    // can't match a key either way and fall back to the literal, as before.
                    Text(LocalizedStringKey(errorMessage))
                        .font(.subheadline)
                        .foregroundStyle(.negative)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                        .animation(.easeInOut, value: errorMessage)
                }
            }

            if let filledCount {
                PINDotsView(filledCount: filledCount)
                    .padding(.top, compact ? 16 : 32)
                    .padding(.bottom, compact ? 0 : 48)
            } else {
                // Steps without PIN dots (biometric prompt, name entry) still need a gap
                // before their content — normally supplied by the dots block above.
                Spacer().frame(height: compact ? 16 : 32)
            }
        }
        // Landscape: the heading takes half the width and the content the rest, so the keypad keeps
        // its natural size instead of being squeezed by a mascot.
        .frame(maxWidth: compact ? .infinity : nil)
    }
}
