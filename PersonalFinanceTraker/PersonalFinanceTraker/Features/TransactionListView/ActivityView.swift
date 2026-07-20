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

    init(showingAddItemView: Binding<Bool>) {
        _showingAddItemView = showingAddItemView
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        return NavigationStack {
            List {
                Section {
                    FilterChipsView()
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

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

                // Bottom spacing for floating tab bar — matches DashboardView and CompassView pattern
                Spacer(minLength: 80)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchText, prompt: "Search transactions...")
            .appToolbar(showingAddItemView: $showingAddItemView)
            .overlay {
                if groupedFiltered.isEmpty && (!viewModel.searchText.isEmpty || viewModel.filters.isActive) {
                    ContentUnavailableView.search(text: viewModel.searchText)
                }
            }
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
