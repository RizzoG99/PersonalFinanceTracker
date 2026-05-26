//
//  ActivityFilterChip.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct ActivityFilterChip: View {
    let label: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2)
                }
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? Color.bg0 : Color.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentIndigo : Color.bg2.opacity(0.6))
            .clipShape(.rect(cornerRadius: 20))
        }
    }
}
