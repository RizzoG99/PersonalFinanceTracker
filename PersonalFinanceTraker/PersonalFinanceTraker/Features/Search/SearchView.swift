//
//  SearchView.swift
//  PersonalFinanceTraker
//
//  Created by Gemini CLI on 26/02/26.
//

import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var viewModel: TransactionListViewModel
    
    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.filteredItems.isEmpty && !viewModel.searchText.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 60))
                            .foregroundStyle(.tertiary)

                        Text("No results for \"\(viewModel.searchText)\"")
                            .font(.headline)

                        Text("Check the spelling or try a different keyword")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // Transaction List
                        ForEach(viewModel.groupedItems, id: \.0) { dateString, dayItems in
                            Section {
                                ForEach(dayItems) { item in
                                    Button(action: {
                                        self.viewModel.transactionToEdit = item
                                    }) {
                                        TransactionItemView(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onDelete { offsets in
                                    withAnimation {
                                        viewModel.deleteItemsFromSection(dayItems: dayItems, offsets: offsets)
                                    }
                                }
                            } header: {
                                TransactionSectionHeader(
                                    dateString: dateString,
                                    totalAmount: viewModel.totalForDate(items: dayItems),
                                    currencyCode: viewModel.currencyService.baseCurrency
                                )
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .appBackground()
            .navigationTitle("Search")
            .searchable(text: $viewModel.searchText)
        }
    }
}

#Preview {
    let schema = Schema([
        TransactionModel.self,
        CategoryModel.self,
    ])
    let container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let viewModel = TransactionListViewModel(repo: TransactionRepository(context: container.mainContext))
    
    // Add sample data
    SampleData.populateModelContext(container.mainContext)
    
    return SearchView()
        .environmentObject(viewModel)
        .modelContainer(container)
}
