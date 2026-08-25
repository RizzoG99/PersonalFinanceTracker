import SwiftUI
import SwiftData

struct EditCategorySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var category: CategoryModel
    let existingCategories: [CategoryModel]

    @State private var editedName: String = ""
    @State private var selectedToken: String = "categoryIndigo"
    @State private var selectedSymbol: String = "creditcard.fill"

    private var nameError: String? {
        let trimmed = editedName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Name cannot be empty" }
        if !CategoryNameValidator.isValid(trimmed) {
            return "Use letters, numbers, spaces, and common punctuation"
        }
        let sameTypeNames = existingCategories
            .filter { $0.id != category.id && $0.transactionType == category.transactionType }
            .map { $0.name }
        if CategoryNameValidator.isDuplicate(trimmed, among: sameTypeNames) {
            return "A category with this name already exists"
        }
        return nil
    }

    private var canSave: Bool {
        nameError == nil && !editedName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Category name", text: $editedName)
                        .autocorrectionDisabled()
                    if let error = nameError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.negative)
                    }
                }
                .appFormSectionBackground()

                Section("Color") {
                    ColorTokenPicker(selectedToken: $selectedToken)
                }
                .appFormSectionBackground()

                Section("Icon") {
                    IconGridPicker(selectedSymbol: $selectedSymbol, colorToken: selectedToken)
                }
                .appFormSectionBackground()

                Section {
                    Button("Delete Category", role: .destructive) {
                        modelContext.delete(category)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
                .appFormSectionBackground()
            }
            .appFormBackground()
            .background { AppBackground() }
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        category.name = editedName.trimmingCharacters(in: .whitespaces)
                        category.systemImage = selectedSymbol
                        category.colorToken = selectedToken
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                editedName = category.name
                selectedToken = category.colorToken
                selectedSymbol = category.systemImage
            }
        }
        .presentationBackground { AppBackground() }
    }
}
