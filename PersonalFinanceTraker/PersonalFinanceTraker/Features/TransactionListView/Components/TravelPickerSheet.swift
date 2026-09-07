//
//  TravelPickerSheet.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// Chooses which travel to move the selected transactions into — or "None" to
/// untag them. Used by the Activity selection bar's Travel action.
struct TravelPickerSheet: View {
    let travels: [TravelSnapshot]
    let onPick: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if travels.isEmpty {
                    ContentUnavailableView(
                        "No travels yet",
                        systemImage: "airplane",
                        description: Text("Create a travel first, from the Travels list or while adding a transaction.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(travels) { travel in
                                Button {
                                    onPick(travel.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: travel.symbolName)
                                            .foregroundStyle(Color.accentIndigo)
                                            .frame(width: 22)
                                        Text(travel.name)
                                            .foregroundStyle(.textPrimary)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                            }
                        }
                        .appFormSectionBackground()

                        // Untagging is the reason this is a list rather than a plain picker:
                        // pulling expenses back out of a travel needs to be as easy as putting
                        // them in, and it is not destructive.
                        Section {
                            Button("Remove from travel", role: .destructive) {
                                onPick(nil)
                            }
                        }
                        .appFormSectionBackground()
                    }
                    .appFormBackground()
                }
            }
            .navigationTitle("Move to Travel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    TravelPickerSheet(
        travels: [
            TravelSnapshot(id: UUID(), name: "Barcellona Travel", symbolName: "airplane"),
            TravelSnapshot(id: UUID(), name: "Dolomites", symbolName: "mountain.2"),
        ],
        onPick: { _ in }
    )
}

#Preview("Empty") {
    TravelPickerSheet(travels: [], onPick: { _ in })
}
