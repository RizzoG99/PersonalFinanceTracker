//
//  TransactionFormTips.swift
//  PersonalFinanceTraker
//
//  One-time, anchored explanations for the icon-only controls in the Add/Edit
//  Transaction sheet's keyboard accessory bar. Each control already carries an
//  accessibilityLabel for VoiceOver — these tips are the sighted-user
//  equivalent, shown once via TipKit's own persistence.
//
//  No tip for the nav-bar save checkmark: a checkmark in `.confirmationAction`
//  is a standard iOS save affordance, and a tip explaining it competed with
//  these three for the same first-run attention and vertical space above the
//  keyboard (UX audit, 2026-08-20) — dropped rather than sequenced, since it
//  wasn't teaching anything a sighted user didn't already know.
//
//  See docs/superpowers/plans/2026-08-08-add-another-transaction-toggle.md for
//  why these controls are icon-only rather than labeled, and issue #31 for why
//  that traded away first-time discoverability.
//

import TipKit

/// Keyboard-bar "add another" toggle. Wording matches the footer caption the
/// control originally shipped with as an inline form Toggle.
///
/// `isEligible` gates it to add-mode, matching the button's own visibility
/// condition (`viewModel.editingItem == nil`) — otherwise a stuck `TipGroup`
/// order could show this in edit mode, where the button doesn't exist.
/// `TransactionFormView` sets it before the group is consulted.
struct AddAnotherTip: Tip {
    @Parameter static var isEligible: Bool = true

    var title: Text { Text("Keep adding") }
    var message: Text? { Text("Keep this sheet open after saving to log several in a row.") }
    // The button's "off" glyph — the tip shows before the user has toggled it on.
    var image: Image? { Image(systemName: "plus.rectangle.on.rectangle") }
    var rules: [Rule] { #Rule(Self.$isEligible) { $0 } }
}

/// Keyboard-bar "Repeat" toggle. `isEligible` mirrors the button's own guard:
/// add-mode and not a transfer.
struct RepeatTip: Tip {
    @Parameter static var isEligible: Bool = true

    var title: Text { Text("Make it recurring") }
    var message: Text? { Text("Repeat this transaction on a schedule.") }
    var image: Image? { Image(systemName: "repeat.circle") }
    var rules: [Rule] { #Rule(Self.$isEligible) { $0 } }
}

/// Keyboard-bar math-mode toggle (the +/- calculator).
struct MathModeTip: Tip {
    var title: Text { Text("Do the math") }
    var message: Text? { Text("Add up a split bill or several receipts without leaving the field.") }
    var image: Image? { Image(systemName: "plus.forwardslash.minus") }
}

/// Nav-bar "Scan receipt" button. Unlike the three tips above, this button lives in the sheet's
/// actual navigation bar rather than the keyboard accessory bar, so a plain `.popoverTip()`
/// anchors from it correctly (the accessory-bar buttons can't use that — see the note above) and
/// none of the `TipGroup`/pinned-card machinery built for those is needed here.
///
/// `isEligible` mirrors the button's own visibility guard (add-mode, not a transfer) — set from
/// `EditAddTransactionView`, which owns that condition, not from this file.
struct ScanReceiptTip: Tip {
    @Parameter static var isEligible: Bool = true

    var title: Text { Text("Scan a receipt") }
    var message: Text? { Text("Fill amount, date, merchant, and category from a photo of a receipt.") }
    var image: Image? { Image(systemName: "doc.text.viewfinder") }
    var rules: [Rule] { #Rule(Self.$isEligible) { $0 } }
}

/// Restyles TipKit's default system-gray card with the app's own palette, so the tip
/// reads as this app's help rather than a generic system popover — same tokens the rest
/// of the form already uses (`surfaceRaised` for the math-expression bubble background,
/// `accentIndigo` for the icon matching the pointer arrow above it, and the same
/// `textDim.opacity(0.3)` stroke `CategoryChip`/`MoreChip` use for their card borders —
/// `hairline` was tried first but reads as barely-there at that opacity, meant for
/// dividers, not a card outline).
struct AppTipViewStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let image = configuration.image {
                image
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentIndigo)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let title = configuration.title {
                    title
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                }
                if let message = configuration.message {
                    message
                        .font(.subheadline)
                        .foregroundStyle(Color.textMid)
                }
            }
            Spacer(minLength: 0)
            Button {
                configuration.tip.invalidate(reason: .tipClosed)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.textDim)
            }
            .buttonStyle(.plain)
        }
        // Matches TipKit's own default TipView insets (20 horizontal, 16 vertical, 16
        // corner radius) — eyeballed against a screenshot of the unstyled TipView so
        // only the background/border/text colors are new, not the layout.
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.textDim.opacity(0.3), lineWidth: 1)
        )
    }
}
