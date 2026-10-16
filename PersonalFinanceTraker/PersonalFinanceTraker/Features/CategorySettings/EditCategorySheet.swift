import SwiftUI
import SwiftData

struct EditCategorySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    /// Optional: not every host injects it, and the rename still lands without the bump.
    @Environment(DataChangedSignal.self) private var dataChanged: DataChangedSignal?
    @Environment(AppSettings.self) private var appSettings: AppSettings?

    @Bindable var category: CategoryModel
    let existingCategories: [CategoryModel]
    let onPersistedCategoryChange: () -> Void

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
            .flatMap { [$0.name, $0.name.localizedCategoryDisplay] }
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
                        guard (try? modelContext.save()) != nil else { return }
                        onPersistedCategoryChange()
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
                        let newName = CategoryNameValidator.renamedName(stored: category.name, edited: editedName)
                        // Name written here too, so this list and a reopened sheet show it at once;
                        // the actor then finds it stored and only rewrites the copies.
                        if let newName { category.name = newName }
                        category.systemImage = selectedSymbol
                        category.colorToken = selectedToken
                        guard (try? modelContext.save()) != nil else { return }
                        onPersistedCategoryChange()
                        if let newName { syncRenamedCategory(newName) }
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                editedName = category.name.localizedCategoryDisplay
                selectedToken = category.colorToken
                selectedSymbol = category.systemImage
            }
        }
        .presentationBackground { AppBackground() }
    }

    /// Rewrites the name copy on this category's transactions and rules, then backs up (#239). Detached: an
    /// actor created from the main actor can end up on the main queue, and a category can own
    /// thousands of rows.
    private func syncRenamedCategory(_ newName: String) {
        let container = modelContext.container
        let id = category.persistentModelID
        let signal = dataChanged
        let settings = appSettings
        Task.detached {
            await TransactionActor.renameAndBackUp(container: container, id: id, to: newName, signal: signal, settings: settings)
        }
    }
}
