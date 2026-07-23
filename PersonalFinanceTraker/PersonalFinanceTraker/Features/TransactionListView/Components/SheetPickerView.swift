//
//  SheetPickerView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct SheetPickerView: View {
    let sheetNames: [String]
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        List(sheetNames, id: \.self) { name in
            Button {
                onSelect(name)
            } label: {
                HStack {
                    Text(name)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
            }
        }
        .navigationTitle("Choose a Sheet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}
