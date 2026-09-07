//
//  TravelFormSheet.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// Create or rename a travel. Deliberately smaller than `AddGoalSheet`: a travel is a
/// folder, so it has nothing to configure but a name and an icon.
struct TravelFormSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var symbolName: String
    @FocusState private var nameFocused: Bool

    private let isEditing: Bool
    private let onSave: (String, String) -> Void

    /// SF Symbols, matching how categories render their icon. A short preset list rather
    /// than a symbol browser: these cover the trip kinds without another picker screen.
    static let symbolChoices = [
        "airplane", "beach.umbrella", "mountain.2", "building.2",
        "car", "tram", "sailboat", "backpack",
    ]

    private static let nameLimit = 24

    init(name: String = "", symbolName: String = "airplane", isEditing: Bool = false, onSave: @escaping (String, String) -> Void) {
        _name = State(initialValue: name)
        _symbolName = State(initialValue: symbolName)
        self.isEditing = isEditing
        self.onSave = onSave
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool { !trimmedName.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Travel name", text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { if isValid { save() } }
                        .onChange(of: name) { _, new in
                            if new.count > Self.nameLimit { name = String(new.prefix(Self.nameLimit)) }
                        }
                }
                .appFormSectionBackground()

                Section("Icon") {
                    symbolPicker
                }
                .appFormSectionBackground()
            }
            .appFormBackground()
            .readableWidth()
            .navigationTitle(isEditing ? "Edit Travel" : "New Travel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // Checkmark in the nav bar, matching AddGoalSheet — a pinned bottom button
                // ends up underneath the keyboard's own accessory bar.
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(isEditing ? "Update Travel" : "Add Travel")
                    .disabled(!isValid)
                }
            }
            .onAppear {
                // Same delayed focus as AddGoalSheet: focusing in the same runloop turn as the
                // sheet's presentation transition is unreliable.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { nameFocused = true }
            }
        }
        // The form is two short rows; a full-height sheet was mostly empty space.
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // Adaptive so the choices wrap instead of shrinking below the 44pt touch target
    // at accessibility Dynamic Type sizes.
    private var symbolPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
            ForEach(Self.symbolChoices, id: \.self) { choice in
                let isSelected = choice == symbolName
                Button {
                    symbolName = choice
                } label: {
                    Image(systemName: choice)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentIndigo : .textMid)
                        .frame(minWidth: 44, minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? Color.accentIndigo.opacity(0.15) : Color.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isSelected ? Color.accentIndigo : Color.hairline, lineWidth: isSelected ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        guard isValid else { return }
        onSave(trimmedName, symbolName)
        dismiss()
    }
}

#Preview("New") {
    TravelFormSheet { _, _ in }
}

#Preview("Edit") {
    TravelFormSheet(name: "Barcellona Travel", symbolName: "beach.umbrella", isEditing: true) { _, _ in }
}
