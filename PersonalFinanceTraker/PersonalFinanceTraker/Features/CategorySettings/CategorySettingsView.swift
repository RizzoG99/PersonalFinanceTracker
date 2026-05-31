//
//  CategorySettingsView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct CategorySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryModel.name) private var categories: [CategoryModel]

    @State private var editingCategory: CategoryModel?
    @State private var showingAddSheet = false

    private var expenseCategories: [CategoryModel] {
        categories.filter { $0.transactionType == .expense }
    }
    private var incomeCategories: [CategoryModel] {
        categories.filter { $0.transactionType == .income }
    }

    var body: some View {
        List {
            Section {
                ForEach(expenseCategories) { category in
                    CategoryRow(category: category) {
                        editingCategory = category
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(category)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                    }
                }
            } header: {
                sectionHeader("Expense Categories")
            }
            .appFormSectionBackground()

            Section {
                ForEach(incomeCategories) { category in
                    CategoryRow(category: category) {
                        editingCategory = category
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(category)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                    }
                }
            } header: {
                sectionHeader("Income Categories")
            }
            .appFormSectionBackground()
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Category", systemImage: "plus") {
                    showingAddSheet = true
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddCategorySheet(existingCategories: categories)
                .environment(\.modelContext, modelContext)
        }
        .sheet(item: $editingCategory) { category in
            EditCategorySheet(category: category, existingCategories: categories)
                .environment(\.modelContext, modelContext)
                .id(category.id)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.textDim)
    }
}
