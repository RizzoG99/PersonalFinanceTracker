//  BudgetsView.swift
//  PersonalFinanceTraker

import SwiftUI
import SwiftData

struct BudgetsView: View {
    @Query(sort: \CategoryModel.name) private var categories: [CategoryModel]
    @FocusState private var focusedCategoryID: PersistentIdentifier?

    private var expenseCategories: [CategoryModel] {
        categories.filter { $0.transactionType == .expense }
    }

    private var totalBudgeted: Decimal {
        expenseCategories.compactMap(\.monthlyBudget).filter { $0 > 0 }.reduce(0, +)
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(expenseCategories) { category in
                        BudgetRow(category: category, isFocused: $focusedCategoryID)
                            .id(category.id)
                    }
                } header: {
                    Text("MONTHLY BUDGET · EXPENSE CATEGORIES")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.textDim)
                } footer: {
                    HStack {
                        Text("Total budgeted")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.textDim)
                        Spacer()
                        Text(totalBudgeted.formatted(.currency(code: "EUR")))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.textPrimary)
                            .privacyBlur()
                    }
                }
                .appFormSectionBackground()

                // Without this, rows near the end of the list have nowhere left to scroll TO:
                // the List's natural scroll extent stops at its last row, so `anchor: .top`
                // below can't lift a near-last row any higher than its resting position, no
                // matter what it's asked for — it's already as far "up" as the List can go. This
                // reserves room past the last row equal to roughly the keyboard + accessory bar's
                // height so every row, including the very last one, can actually reach the top.
                Color.clear
                    .frame(height: 320)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("Budgets")
            .navigationBarTitleDisplayMode(.inline)
            // Same glass-capsule bar as Add/Edit Transaction and the Goal sheet, not the bare
            // system "Done" pill. Chevrons route through `navigate`, same as those two: scroll
            // the target row into view and wait for the scroll to settle before requesting focus
            // — a row currently off-screen doesn't reliably take focus from a bare FocusState
            // assignment.
            .keyboardFieldNavigation($focusedCategoryID, order: expenseCategories.map(\.id), navigate: { id in
                withAnimation {
                    // .top, not .center: centering only leaves room for the raw keyboard, not
                    // the accessory bar's extra height above it (same reasoning as the onChange
                    // below) — this is the same fix, just reached via the chevrons instead of a
                    // direct tap.
                    proxy.scrollTo(id, anchor: .top)
                } completion: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        focusedCategoryID = id
                    }
                }
            })
            // Direct taps skip `navigate` (they already know where they landed), but the row can
            // still end up right behind the accessory bar's extra height above the keyboard —
            // same fix as TransactionFormView's Name field: anchor to the row's top edge, not
            // its center, so the rest of the viewport is clearance instead of just the raw
            // keyboard's height.
            .onChange(of: focusedCategoryID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    return NavigationStack { BudgetsView() }
        .modelContainer(container)
        .environment(DataChangedSignal())
        .preferredColorScheme(.dark)
}
