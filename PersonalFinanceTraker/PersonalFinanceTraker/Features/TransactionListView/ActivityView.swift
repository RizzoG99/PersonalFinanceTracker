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
                    if !viewModel.hasNoTransactions {
                        FilterChipsView()
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    if viewModel.totalFilteredIncome == 0 && viewModel.totalFilteredExpenses == 0 {
                        if viewModel.hasNoTransactions {
                            EmptyStateView(
                                icon: "tray",
                                message: "No transactions yet",
                                subtitle: "Add your first transaction to start tracking.",
                                actionTitle: "Add Transaction",
                                action: { showingAddItemView = true }
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
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
                            // Recurring rows must not use role: .destructive here — iOS plays the
                            // swipe-to-delete row-collapse animation the instant a destructive-role
                            // swipe action is tapped, regardless of whether the closure actually
                            // deletes anything. For a recurring item we need to ask "this transaction"
                            // vs. "this and future" first, so the row must stay put until the user
                            // chooses; a plain button (red-tinted, no destructive role) avoids the
                            // automatic collapse.
                            //
                            // The confirmationDialog itself must live on this row's main Button, not
                            // on the swipeActions button — SwiftUI bridges swipeActions content to
                            // UIContextualAction under the hood, and presentation modifiers attached
                            // there silently fail to present.
                            .confirmationDialog(
                                "This is part of a recurring series",
                                isPresented: Binding(
                                    get: { viewModel.pendingRecurrenceDeletion?.id == item.id },
                                    set: { if !$0 { viewModel.pendingRecurrenceDeletion = nil } }
                                ),
                                titleVisibility: .visible
                            ) {
                                Button("This transaction", role: .destructive) {
                                    viewModel.applyRecurrenceDeletionScope(.thisOnly)
                                }
                                Button("This and future", role: .destructive) {
                                    viewModel.applyRecurrenceDeletionScope(.thisAndFuture)
                                }
                                Button("Cancel", role: .cancel) {
                                    viewModel.pendingRecurrenceDeletion = nil
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: item.recurrenceRuleId == nil) {
                                if item.recurrenceRuleId != nil {
                                    Button {
                                        viewModel.pendingRecurrenceDeletion = item
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                } else {
                                    Button(role: .destructive) {
                                        viewModel.delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                            }
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
            .modifier(ConditionalSearchable(
                isActive: !viewModel.hasNoTransactions,
                text: $viewModel.searchText,
                prompt: "Search transactions..."
            ))
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

private struct ConditionalSearchable: ViewModifier {
    let isActive: Bool
    @Binding var text: String
    let prompt: LocalizedStringKey

    func body(content: Content) -> some View {
        if isActive {
            content.searchable(text: $text, prompt: prompt)
        } else {
            content
        }
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    let vm = TransactionListViewModel(repo: TransactionActor.make(container))
    return ActivityView(showingAddItemView: .constant(false))
        .environment(vm)
        .environment(ProfileViewModel())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
