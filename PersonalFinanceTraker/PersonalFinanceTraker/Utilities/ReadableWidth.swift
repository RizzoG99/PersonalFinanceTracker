//
//  ReadableWidth.swift
//  PersonalFinanceTraker
//

import SwiftUI

extension View {
    /// Caps content to a comfortable reading measure and centers it — the double-`frame`
    /// idiom. Without this, forms and detail panes stretch edge-to-edge in regular-width
    /// contexts (iPad, page sheets, split-view panes), which hurts scanability at long line
    /// lengths (HIG readable-content guidance).
    func readableWidth(_ max: CGFloat = 640) -> some View {
        self.frame(maxWidth: max).frame(maxWidth: .infinity)
    }
}
