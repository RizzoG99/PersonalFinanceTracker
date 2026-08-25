import SwiftUI
import SwiftData

struct AddCategorySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existingCategories: [CategoryModel]
    let onAdd: (CategoryModel) -> Void

    @State private var name = ""
    @State private var selectedToken = "categoryIndigo"
    @State private var selectedSymbol = "creditcard.fill"
    @State private var selectedType: TransactionType

    init(
        existingCategories: [CategoryModel],
        initialType: TransactionType = .expense,
        onAdd: @escaping (CategoryModel) -> Void = { _ in }
    ) {
        self.existingCategories = existingCategories
        self.onAdd = onAdd
        _selectedType = State(initialValue: initialType)
    }

    private var nameError: String? {
        if name.isEmpty { return nil }
        if !CategoryNameValidator.isValid(name) {
            return "Use letters, numbers, spaces, and common punctuation"
        }
        if existingCategories.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            return "A category with this name already exists"
        }
        return nil
    }

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && nameError == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Category name", text: $name)
                        .autocorrectionDisabled()
                    if let error = nameError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.negative)
                    }
                }
                .appFormSectionBackground()

                Section("Type") {
                    Picker("Type", selection: $selectedType) {
                        Text("Expense").tag(TransactionType.expense)
                        Text("Income").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
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
            }
            .appFormBackground()
            .background { AppBackground() }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let category = CategoryModel(
                            name: name.trimmingCharacters(in: .whitespaces),
                            systemImage: selectedSymbol,
                            type: selectedType,
                            colorToken: selectedToken
                        )
                        modelContext.insert(category)
                        try? modelContext.save()
                        onAdd(category)
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
        .presentationBackground { AppBackground() }
    }
}
