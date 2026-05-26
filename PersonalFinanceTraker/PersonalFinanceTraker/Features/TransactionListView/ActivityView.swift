//
//  ActivityView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct ActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var viewModel: TransactionListViewModel
    @Binding var showingAddItemView: Bool
    @State private var selectedCategory: String? = nil

    init(context: ModelContext, showingAddItemView: Binding<Bool>) {
        _showingAddItemView = showingAddItemView
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ActivityFilterChip(label: "All", isSelected: selectedCategory == nil) {
                                selectedCategory = nil
                            }
                            ForEach(availableCategories, id: \.self) { category in
                                let info = CategoryInfo.info(for: category)
                                ActivityFilterChip(
                                    label: category,
                                    systemImage: info.symbol,
                                    isSelected: selectedCategory == category
                                ) {
                                    selectedCategory = selectedCategory == category ? nil : category
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    HStack(spacing: 12) {
                        StatCard(
                            icon: "arrow.down",
                            label: "Income",
                            value: formatEUR(viewModel.filteredItems.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }),
                            color: .positive
                        )
                        StatCard(
                            icon: "arrow.up",
                            label: "Expenses",
                            value: formatEUR(abs(viewModel.filteredItems.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + $1.amount })),
                            color: .negative
                        )
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

    private var availableCategories: [String] {
        let all = viewModel.filteredItems.map(\.category)
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }

    private var groupedFiltered: [(String, [TransactionModel])] {
        guard let category = selectedCategory else { return viewModel.groupedItems }
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
    let vm = TransactionListViewModel(repo: TransactionRepository(context: container.mainContext))
    return ActivityView(context: container.mainContext, showingAddItemView: .constant(false))
        .environmentObject(vm)
        .environmentObject(ProfileViewModel())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
