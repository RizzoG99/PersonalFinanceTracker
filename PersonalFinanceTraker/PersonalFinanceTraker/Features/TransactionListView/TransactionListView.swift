//
//  TransactionListMVVM.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 14/10/25.
//

import SwiftUI
import SwiftData

struct TransactionListMVVM: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var viewModel: TransactionListViewModel
    @Binding private var showingAddItemView: Bool
    @State private var editMode: EditMode = .inactive
    
    init(showingAddItemView: Binding<Bool>) {
        _showingAddItemView = showingAddItemView
    }
    
    var body: some View {
        NavigationView {
            List {
                // Chart Section
                Section {
                    VStack(spacing: 16) {
                        TimePeriodPicker(selection: $viewModel.selectedTimePeriod)
                        
                        TransactionChart(
                            data: viewModel.chartData,
                            currencyCode: "EUR"
                        )
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Transaction Summary")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
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
                            currencyCode: "EUR"
                        )
                    }
                }
            }
            .navigationTitle("Transactions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem {
                    EditButton()
                }
                ToolbarSpacer(.fixed)
                ToolbarItem {
                    Button(action: {
                        showingAddItemView.toggle()
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .onAppear {
            viewModel.load()
        }
    }

}
