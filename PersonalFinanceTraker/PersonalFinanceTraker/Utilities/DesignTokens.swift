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
    static let formRow = Color.white.opacity(0.06)

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
    static var formRow: Color { .formRow }
}

// MARK: - App Background

// Matches the Claude Design spec:
// base #030712 with radial blooms — indigo at top-left (22%), teal at bottom-right (10%), indigo at center (10%)
struct AppBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.012, green: 0.027, blue: 0.071)

                // Indigo bloom — top-left (ellipse at 20% 0%)
                RadialGradient(
                    colors: [
                        Color(red: 0.506, green: 0.549, blue: 0.973).opacity(0.22),
                        .clear
                    ],
                    center: UnitPoint(x: 0.2, y: 0),
                    startRadius: 0,
                    endRadius: geo.size.height * 0.55
                )

                // Teal bloom — bottom-right (ellipse at 80% 100%)
                RadialGradient(
                    colors: [
                        Color(red: 0.133, green: 0.827, blue: 0.627).opacity(0.10),
                        .clear
                    ],
                    center: UnitPoint(x: 0.8, y: 1.0),
                    startRadius: 0,
                    endRadius: geo.size.height * 0.55
                )

                // Indigo bloom — center (ellipse at 50% 50%)
                RadialGradient(
                    colors: [
                        Color(red: 0.388, green: 0.400, blue: 0.945).opacity(0.10),
                        .clear
                    ],
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
                    .accessibilityLabel("Amount hidden")
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
