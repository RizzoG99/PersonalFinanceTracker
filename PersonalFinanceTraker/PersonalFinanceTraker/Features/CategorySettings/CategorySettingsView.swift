//
//  CategorySettingsView.swift
//  PersonalFinanceTraker
//
//  Created by Gemini CLI on 26/02/26.
//

import SwiftUI
import SwiftData

struct CategorySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryModel.name) private var categories: [CategoryModel]
    @Environment(\.dismiss) private var dismiss
    
    @State private var editingCategory: CategoryModel?
    @State private var showingEditSheet = false
    
    // New category state
    @State private var newName = ""
    @State private var newSystemImage = "questionmark"
    @State private var newType: TransactionType = .expense
    @State private var newBudget: String = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section("Expense Categories") {
                    ForEach(categories.filter { $0.transactionType == .expense }) { category in
                        CategoryRow(category: category) {
                            startEditing(category)
                        }
                    }
                }
                
                Section("Income Categories") {
                    ForEach(categories.filter { $0.transactionType == .income }) { category in
                        CategoryRow(category: category) {
                            startEditing(category)
                        }
                    }
                }
                
                Section("Add New Category") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("Category Name", text: $newName)
                            TextField("SF Symbol", text: $newSystemImage)
                                .frame(width: 120)
                                .multilineTextAlignment(.center)
                        }
                        
                        Picker("Type", selection: $newType) {
                            Text("Expense").tag(TransactionType.expense)
                            Text("Income").tag(TransactionType.income)
                        }
                        .pickerStyle(.segmented)
                        
                        TextField("Monthly Budget (Optional)", text: $newBudget)
                            .keyboardType(.decimalPad)
                        
                        Button("Add Category") {
                            addCategory()
                        }
                        .disabled(newName.isEmpty)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle("Manage Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                if let category = editingCategory {
                    EditCategorySheet(category: category)
                }
            }
        }
    }
    
    private func startEditing(_ category: CategoryModel) {
        editingCategory = category
        showingEditSheet = true
    }
    
    private func addCategory() {
        let budget = Decimal(string: newBudget)
        let newCat = CategoryModel(name: newName, systemImage: newSystemImage, type: newType, monthlyBudget: budget)
        modelContext.insert(newCat)
        
        // Reset
        newName = ""
        newSystemImage = "questionmark"
        newBudget = ""
    }
}

struct CategoryRow: View {
    let category: CategoryModel
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: category.systemImage)
                Text(category.name)
                Spacer()
                if let budget = category.monthlyBudget {
                    Text(budget, format: .currency(code: "EUR").precision(.fractionLength(0)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.blue)
            }
        }
        .buttonStyle(.plain)
    }
}

struct EditCategorySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var category: CategoryModel
    @State private var budgetString: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $category.name)
                    TextField("System Image", text: $category.systemImage)
                }
                
                Section("Budget") {
                    TextField("Monthly Budget", text: $budgetString)
                        .keyboardType(.decimalPad)
                        .onChange(of: budgetString) { _, newValue in
                            category.monthlyBudget = Decimal(string: newValue)
                        }
                }
                
                Section {
                    Button("Delete Category", role: .destructive) {
                        modelContext.delete(category)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let budget = category.monthlyBudget {
                    budgetString = "\(budget)"
                }
            }
        }
    }
}
