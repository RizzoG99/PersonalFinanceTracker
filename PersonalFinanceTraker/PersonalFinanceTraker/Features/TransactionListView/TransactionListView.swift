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
    @Environment(TransactionListViewModel.self) private var viewModel: TransactionListViewModel
    @Binding private var showingAddItemView: Bool
    @State private var editMode: EditMode = .inactive

    init(showingAddItemView: Binding<Bool>) {
        _showingAddItemView = showingAddItemView
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        return NavigationView {
            List {
                // Chart Section
                Section {
                    VStack(spacing: 16) {
                        TimePeriodPicker(selection: $viewModel.selectedTimePeriod)

                        if let label = viewModel.currentPeriodLabel {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }

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
                            currencyCode: viewModel.currencyService.baseCurrency
                        )
                    }
                }

                // Bottom spacer to clear floating tab bar
                Section {
                    Color.clear.frame(height: 80)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Transactions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    let csvData = viewModel.exportCSV()
                    ShareLink(item: csvData, preview: SharePreview("Transactions.csv")) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        showingAddItemView.toggle()
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.showUndoBanner {
                UndoDeleteBanner(
                    count: viewModel.pendingDeletion.count,
                    progress: viewModel.deleteProgress,
                    onUndo: viewModel.undoDelete
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 90) // ponytail: clears floating tab bar; safeAreaInset doesn't pierce TabView's floating layer
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.showUndoBanner)
        .task { viewModel.load() }
    }

}

struct UndoDeleteBanner: View {
    let count: Int
    let progress: Double
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)

            Text("\(count) transaction\(count == 1 ? "" : "s") deleted")
                .font(.subheadline)

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 1 - progress)
                    .stroke(Color.white, lineWidth: 2)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: progress)
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)

            Button("Undo", action: onUndo)
                .font(.subheadline.bold())
                .tint(.accentColor)
                .accessibilityLabel("Undo delete")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.75))
        }
        .foregroundStyle(.white)
    }
}
