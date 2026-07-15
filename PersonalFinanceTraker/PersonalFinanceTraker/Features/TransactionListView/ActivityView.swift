//
//  ActivityView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct ActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TransactionListViewModel.self) private var viewModel: TransactionListViewModel
    @Binding var showingAddItemView: Bool

    private func categorySymbol(for categoryName: String) -> String {
        viewModel.filteredItems
            .first(where: { $0.category == categoryName })?.categorySystemImage
            ?? CategoryInfo.info(for: categoryName).symbol
    }

    init(showingAddItemView: Binding<Bool>) {
        _showingAddItemView = showingAddItemView
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        return NavigationStack {
            List {
                Section {
                    // ponytail: chips live in the scroll content — any pinned-bar backdrop clashes with the gradient
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ActivityFilterChip(label: "All", isSelected: viewModel.effectiveCategory == nil) {
                                viewModel.selectedCategory = nil
                            }
                            ForEach(viewModel.filterCategories, id: \.self) { category in
                                ActivityFilterChip(
                                    label: category.removingLeadingEmoji,
                                    systemImage: categorySymbol(for: category),
                                    isSelected: viewModel.effectiveCategory == category
                                ) {
                                    viewModel.selectedCategory = viewModel.selectedCategory == category ? nil : category
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets())

                    if viewModel.totalFilteredIncome == 0 && viewModel.totalFilteredExpenses == 0 {
                        Text("No transactions yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    } else {
                        HStack(spacing: 12) {
                            StatCard(
                                icon: "arrow.down.left",
                                label: "Income",
                                value: viewModel.totalFilteredIncome.formattedEUR(),
                                color: .positive
                            )
                            StatCard(
                                icon: "arrow.up.right",
                                label: "Expenses",
                                value: viewModel.totalFilteredExpenses.formattedEUR(),
                                color: .negative
                            )
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)

                ForEach(groupedFiltered, id: \.0) { dateString, dayItems in
                    Section {
                        ForEach(dayItems) { item in
                            Button {
                                viewModel.transactionToEdit = item
                            } label: {
                                TransactionItemView(item: item)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                        .onDelete { offsets in
                            viewModel.deleteItemsFromSection(dayItems: dayItems, offsets: offsets)
                        }
                    } header: {
                        Text(dateString)
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchText, prompt: "Search transactions...")
            .appToolbar(showingAddItemView: $showingAddItemView)
            .onAppear { viewModel.load() }
        }
    }

    private var groupedFiltered: [(String, [TransactionSnapshot])] {
        guard let category = viewModel.effectiveCategory else { return viewModel.groupedItems }
        return viewModel.groupedItems.compactMap { (dateString, items) in
            let filtered = items.filter { $0.category == category }
            return filtered.isEmpty ? nil : (dateString, filtered)
        }
    }
}


#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    let vm = TransactionListViewModel(repo: TransactionActor.make(container))
    return ActivityView(showingAddItemView: .constant(false))
        .environment(vm)
        .environment(ProfileViewModel())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
