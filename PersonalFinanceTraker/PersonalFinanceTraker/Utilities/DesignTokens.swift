//
//  DesignTokens.swift
//  PersonalFinanceTraker
//

import SwiftUI

// MARK: - Color Tokens

extension Color {
    static let bg0 = Color("bg0")
    static let bg1 = Color("bg1")
    static let bg2 = Color("bg2")
    static let accentIndigo = Color("accentIndigo")

    /// Foreground for controls using the saturated indigo action tint. It must not
    /// follow the screen's adaptive ink token: that becomes dark text on indigo in
    /// light appearance.
    static let primaryActionForeground = Color.white
    static let positive = Color("positive")
    static let negative = Color("negative")
    static let textPrimary = Color("textPrimary")
    static let textMid = Color("textMid")
    static let textDim = Color("textDim")
    static let categoryGreen = Color("categoryGreen")
    static let categoryAmber = Color("categoryAmber")
    static let categoryIndigo = Color("categoryIndigo")
    static let categoryPink = Color("categoryPink")
    static let categoryPurple = Color("categoryPurple")
    static let categoryTeal = Color("categoryTeal")
    static let categoryGray = Color("categoryGray")

    /// Subtle 1pt strokes, dividers and chart grid lines. White-on-dark / ink-on-light,
    /// so it stays visible in both appearances — a raw `Color.white.opacity(…)` does not.
    static let hairline = Color("hairline")

    /// Low-elevation fills: form rows, gauge tracks, unselected chips.
    static let surfaceRaised = Color("surfaceRaised")

    /// The base colour behind `AppBackground`'s gradient blooms. Shares the
    /// `LaunchBackground` colorset on purpose: the launch screen and the app's base
    /// must be the same colour or the launch→SwiftUI handoff flashes.
    static let appBackgroundBase = Color("LaunchBackground")

    static let formRow = Color.surfaceRaised

    /// Safe category token lookup — validates token exists, falls back to categoryIndigo if not found.
    /// Prevents "No color named 'X' found in asset catalog" runtime errors.
    init(categoryToken: String) {
        let validTokens = Set(CategoryConstants.colorTokenNames)
        let safeToken = validTokens.contains(categoryToken) ? categoryToken : "categoryIndigo"
        self.init(safeToken)
    }
}

extension ShapeStyle where Self == Color {
    static var bg0: Color { .bg0 }
    static var bg1: Color { .bg1 }
    static var bg2: Color { .bg2 }
    static var accentIndigo: Color { .accentIndigo }
    static var primaryActionForeground: Color { .primaryActionForeground }
    static var positive: Color { .positive }
    static var negative: Color { .negative }
    static var textPrimary: Color { .textPrimary }
    static var textMid: Color { .textMid }
    static var textDim: Color { .textDim }
    static var categoryGreen: Color { .categoryGreen }
    static var categoryAmber: Color { .categoryAmber }
    static var categoryIndigo: Color { .categoryIndigo }
    static var categoryPink: Color { .categoryPink }
    static var categoryPurple: Color { .categoryPurple }
    static var categoryTeal: Color { .categoryTeal }
    static var categoryGray: Color { .categoryGray }
    static var hairline: Color { .hairline }
    static var surfaceRaised: Color { .surfaceRaised }
    static var appBackgroundBase: Color { .appBackgroundBase }
    static var formRow: Color { .formRow }
}

// MARK: - App Background

// Matches the Claude Design spec:
// base + radial blooms — indigo at top-left, teal at bottom-right, indigo at centre.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct Bloom {
        let color: Color
        let opacity: Double
    }

    // The one legitimate colorScheme branch in the app: a gradient can't live in the
    // asset catalog.
    //
    // The two themes bloom in opposite directions. Dark adds light to a near-black
    // base, so a strong bloom costs nothing. Light originally added the same
    // saturated indigo to a pale base, which *darkened* the backdrop toward the
    // text — so the opacities had to be cut to ~a quarter to protect contrast, and
    // the gradient became invisible.
    //
    // Light now blooms *lighter than its base* instead. That inverts the trade: the
    // worst case for text is the unbloomed base, which is a fixed known value, so
    // bloom strength no longer competes with the contrast budget at all and the
    // opacities can be an order of magnitude higher.
    private var blooms: (topLeft: Bloom, bottomRight: Bloom, centre: Bloom) {
        if colorScheme == .dark {
            (Bloom(color: Color(red: 0.506, green: 0.549, blue: 0.973), opacity: 0.22),
             Bloom(color: Color(red: 0.133, green: 0.827, blue: 0.627), opacity: 0.10),
             Bloom(color: Color(red: 0.388, green: 0.400, blue: 0.945), opacity: 0.10))
        } else {
            // Pale indigo #EEF0FF and pale teal #EAF7F3 — both lighter than the
            // #DCE0EE base, so every bloomed region has *more* contrast with text
            // than the base does, not less.
            (Bloom(color: Color(red: 0.933, green: 0.941, blue: 1.000), opacity: 0.55),
             Bloom(color: Color(red: 0.918, green: 0.969, blue: 0.953), opacity: 0.35),
             Bloom(color: Color(red: 0.933, green: 0.941, blue: 1.000), opacity: 0.35))
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.appBackgroundBase

                // Indigo bloom — top-left (ellipse at 20% 0%)
                RadialGradient(
                    colors: [blooms.topLeft.color.opacity(blooms.topLeft.opacity), .clear],
                    center: UnitPoint(x: 0.2, y: 0),
                    startRadius: 0,
                    endRadius: geo.size.height * 0.55
                )

                // Teal bloom — bottom-right (ellipse at 80% 100%)
                RadialGradient(
                    colors: [blooms.bottomRight.color.opacity(blooms.bottomRight.opacity), .clear],
                    center: UnitPoint(x: 0.8, y: 1.0),
                    startRadius: 0,
                    endRadius: geo.size.height * 0.55
                )

                // Indigo bloom — centre (ellipse at 50% 50%)
                RadialGradient(
                    colors: [blooms.centre.color.opacity(blooms.centre.opacity), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: geo.size.height * 0.60
                )
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    func appBackground() -> some View {
        self.background { AppBackground() }
    }

    /// Hides the default Form/List chrome background so AppBackground shows through.
    func appFormBackground() -> some View {
        self.scrollContentBackground(.hidden)
    }

    /// Applies the standard app row background to a Form Section or list row.
    func appFormSectionBackground() -> some View {
        self.listRowBackground(Color.formRow)
    }
}

// MARK: - Privacy Blur (shake-to-hide amounts)

private struct PrivacyBlur: ViewModifier {
    // Optional: previews/hosts that don't inject AppSettings just render unblurred,
    // rather than crashing.
    @Environment(AppSettings.self) private var settings: AppSettings?
    let radius: CGFloat

    func body(content: Content) -> some View {
        let hidden = settings?.hideAmounts ?? false
        Group {
            if hidden {
                // Mask the value from VoiceOver too — a visual blur alone still lets
                // the screen reader speak the real amount aloud. Both label AND value
                // need overriding: a view like a TextField carries its own
                // accessibilityValue independent of the label, and that value would
                // otherwise still announce the real amount. Only overridden while
                // hidden, so the view's own accessibility label/value is untouched
                // the rest of the time.
                content
                    .accessibilityLabel(String(localized: "Amount hidden"))
                    .accessibilityValue("")
            } else {
                content
            }
        }
        .blur(radius: hidden ? radius : 0)
        .opacity(hidden ? 0.85 : 1)
        .animation(.easeInOut(duration: 0.25), value: hidden)
    }
}

extension View {
    /// Blurs an amount when privacy mode (`AppSettings.hideAmounts`) is on. Use the
    /// default radius (~6) for small row/list amounts; pass ~8 for large hero totals.
    func privacyBlur(radius: CGFloat = 6) -> some View {
        modifier(PrivacyBlur(radius: radius))
    }
}

// MARK: - Toast Banner

/// Shared black-pill toast used for transient status/undo messages. Convention: place
/// informational-only toasts (no `action`) near the top; actionable/destructive-adjacent
/// ones (with an `action`) near the bottom, close to the thumb.
///
/// No `Spacer` between message and `action` here — that's the caller's job (see
/// `UndoDeleteBanner`, which prepends one to push its content to the trailing edge). A
/// shared unconditional `Spacer` would still expand to fill all available width even when
/// `action` is `EmptyView`, stretching a plain icon+text toast into a full-width bar
/// instead of a compact, content-hugging pill.
///
/// Does NOT combine its accessibility children by default — an `action` slot may contain
/// an interactive control (e.g. an Undo button), and `.accessibilityElement(children: .combine)`
/// would swallow it into one non-interactive element, making it untappable via VoiceOver.
/// Callers with no interactive action (icon + text only) can safely add
/// `.accessibilityElement(children: .combine)` themselves at the call site.
struct ToastBanner<Action: View>: View {
    let icon: String
    let message: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
            Text(message)
                .font(.subheadline.weight(.semibold))
            action()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Capsule().fill(Color.black.opacity(0.75))
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Glass Card Component

struct GlassCard<Content: View>: View {
    let tint: Color?
    let content: Content
    let type: Glass
    let borderRadius: CGFloat
    
    init(tint: Color? = nil,
         type: Glass = .regular,
         borderRadius: CGFloat = 26,
         @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
        self.type = type
        self.borderRadius = borderRadius
    }

    private var glass: Glass {
        if let tint {
            return self.type.tint(tint)
        }
        return self.type
    }

    var body: some View {
        content
            .padding(16)
            .glassEffect(glass, in: .rect(cornerRadius: borderRadius))
            .glassEffectTransition(.materialize)
    }
}

// MARK: - Category Info

struct CategoryInfo {
    let color: Color
    let symbol: String

    static func info(for categoryName: String) -> CategoryInfo {
        let name = categoryName.lowercased()

        let color = Color(CategoryConstants.colorToken(forName: categoryName))

        let symbol: String
        if name.contains("grocer") || name.contains("supermarket") {
            symbol = "cart.fill"
        } else if name.contains("dining") || name.contains("restaurant") || name.contains("food") {
            symbol = "fork.knife"
        } else if name.contains("coffee") {
            symbol = "cup.and.saucer.fill"
        } else if name.contains("transport") || (name.contains("car") && !name.contains("health")) || name.contains("uber") {
            symbol = "car.fill"
        } else if name.contains("shopping") || name.contains("clothing") {
            symbol = "bag.fill"
        } else if name.contains("subscription") || name.contains("streaming") || name.contains("netflix") || name.contains("spotify") {
            symbol = "play.circle.fill"
        } else if name.contains("health") || name.contains("healthcare") {
            symbol = "cross.case.fill"
        } else if name.contains("gym") || name.contains("fitness") {
            symbol = "figure.run"
        } else if name.contains("salary") || name.contains("paycheck") {
            symbol = "banknote.fill"
        } else if name.contains("freelance") {
            symbol = "laptopcomputer"
        } else if name.contains("gift") {
            symbol = "gift.fill"
        } else if name.contains("investment") || name.contains("bonus") {
            symbol = "chart.line.uptrend.xyaxis"
        } else if name.contains("prize") || name.contains("refund") {
            symbol = "arrow.turn.down.left"
        } else if name.contains("rent") || name.contains("mortgage") {
            symbol = "house.fill"
        } else if name.contains("utilities") || name.contains("electricity") {
            symbol = "bolt.fill"
        } else if name.contains("phone") {
            symbol = "phone.fill"
        } else if name.contains("entertainment") || name.contains("movie") {
            symbol = "film.fill"
        } else if name.contains("pet") {
            symbol = "pawprint.fill"
        } else if name.contains("travel") || name.contains("airplane") {
            symbol = "airplane"
        } else {
            symbol = "creditcard.fill"
        }

        return CategoryInfo(color: color, symbol: symbol)
    }
}
