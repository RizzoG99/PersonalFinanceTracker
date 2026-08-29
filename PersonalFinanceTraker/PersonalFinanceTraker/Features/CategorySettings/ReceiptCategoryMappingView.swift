//
//  ReceiptCategoryMappingView.swift
//  PersonalFinanceTraker
//
//  Lets the user say, once, which of *their* categories each kind of receipt belongs to.
//
//  Needed because categories are user-created and user-renamed, while every automatic tier
//  ultimately matches a concept against category *names* through a fixed multilingual synonym list.
//  Rename "Restaurant" to "Uscite varie", or create "Gelati", and the scan can identify the shop
//  perfectly yet still fill in the wrong category. See `ReceiptCategoryMap`.
//
//  Every row is optional. An unset concept simply falls through to the automatic matching that
//  already exists, so this screen is worth opening but never required.
//

import SwiftData
import SwiftUI

struct ReceiptCategoryMappingView: View {
    @Query(sort: \CategoryModel.name) private var categories: [CategoryModel]

    /// Only expense categories: every concept here is a kind of spending, and offering income
    /// categories would let the user build a pairing a scan can never use.
    private var expenseCategories: [CategorySnapshot] {
        categories.filter { $0.transactionType == .expense }.map(CategorySnapshot.init)
    }

    var body: some View {
        Form {
            Section {
                ForEach(ReceiptCategoryConcept.allCases) { concept in
                    ConceptRow(concept: concept, categories: expenseCategories)
                }
            } header: {
                Text("RECEIPT TYPE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.textDim)
            } footer: {
                Text("Anything left unset is matched automatically from the category name.")
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
            .appFormSectionBackground()
        }
        .appFormBackground()
        .readableWidth()
        .navigationTitle("Scan Categories")
        .navigationBarTitleDisplayMode(.inline)
        // A category deleted since the last visit would otherwise leave a pairing pointing at
        // nothing, which reads as "I set this" while behaving as "unset".
        .onAppear { ReceiptCategoryMap.prune(against: expenseCategories) }
    }
}

/// One concept and the category the user paired it with. Holds its own selection so changing one
/// row does not re-render the whole form.
private struct ConceptRow: View {
    let concept: ReceiptCategoryConcept
    let categories: [CategorySnapshot]

    @State private var selection: UUID?

    var body: some View {
        Picker(selection: $selection) {
            Text("Automatic").tag(UUID?.none)
            ForEach(categories) { category in
                Text(category.name).tag(UUID?.some(category.id))
            }
        } label: {
            Label {
                Text(concept.title)
            } icon: {
                Image(systemName: concept.systemImage)
                    .foregroundStyle(.accentIndigo)
            }
        }
        .onAppear { selection = ReceiptCategoryMap.categoryId(for: concept) }
        .onChange(of: selection) { _, newValue in
            ReceiptCategoryMap.setCategoryId(newValue, for: concept)
        }
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self, CreditCardModel.self, GoalModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    return NavigationStack {
        ReceiptCategoryMappingView()
    }
    .modelContainer(container)
}
