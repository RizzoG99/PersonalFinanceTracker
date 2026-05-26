//
//  ActivitySearchBar.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct ActivitySearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.textDim)
            TextField("Search transactions...", text: $text)
                .foregroundStyle(.textPrimary)
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.textDim)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(Color.bg2.opacity(0.6)).interactive())
    }
}
