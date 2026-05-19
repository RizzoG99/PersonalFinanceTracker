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
    @State private var offset: CGFloat = 0
    @State private var showStatBalances: Bool = true
    private let defaultHeight: CGFloat = 124

    init(context: ModelContext, showingAddItemView: Binding<Bool>) {
        _showingAddItemView = showingAddItemView
    }

    var headerList: some View {
        let balanceHeight = showStatBalances ? 44.0 : 0
        let headerHeight = defaultHeight + balanceHeight + max(0, -offset)
        return VStack(spacing: 12) {
            // Search bar
            ActivitySearchBar(text: $viewModel.searchText)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ActivityFilterChip(label: "All", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(availableCategories, id: \.self) { category in
                        let info = CategoryInfo.info(for: category)
                        ActivityFilterChip(label: category, systemImage: info.symbol, isSelected: selectedCategory == category) {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }
                }
            }
            // Stats row
            if (showStatBalances) {
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
                .transition(.blurReplace)
            }
        }
        .padding(.bottom, 12)
        .padding(.horizontal, 24)
        .transition(.scale)
        .frame(height: headerHeight)
        .frame(maxWidth: .infinity)
    }
    
    var body: some View {
        let balanceHeight = showStatBalances ? 44.0 : 0
        let headerHeight = defaultHeight + balanceHeight + max(0, -offset)
        
        NavigationStack {
            VStack(spacing: 0) {
                Color.clear.frame(height: headerHeight)

                List {
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
                                .foregroundColor(.textPrimary)
                        }
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                    return geometry.contentOffset.y + geometry.contentInsets.top
                }, action: { _, new in
                    self.offset = new
                    let isReachingTop = offset < 100
                    let isValueDifferent = isReachingTop != showStatBalances
                    if isValueDifferent {
                        withAnimation {
                            showStatBalances = offset < 100
                        }
                    }
                })
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .appBackground()
            .toolbarVisibility(.hidden, for: .navigationBar)
            .onAppear { viewModel.load() }
        }
        .overlay(alignment: .top) { headerList }
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

// MARK: - Subcomponents

struct ActivitySearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.textDim)
            TextField("Search transactions...", text: $text)
                .foregroundColor(.textPrimary)
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.textDim)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(Color.bg2.opacity(0.6)).interactive())
    }
}

struct ActivityFilterChip: View {
    let label: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2)
                }
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? Color.bg0 : Color.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentIndigo : Color.bg2.opacity(0.6))
            .cornerRadius(20)
        }
    }
}

private func formatEUR(_ value: Decimal) -> String {
    let fmt = NumberFormatter()
    fmt.numberStyle = .currency
    fmt.currencyCode = "EUR"
    return fmt.string(from: value as NSDecimalNumber) ?? "€0.00"
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    let vm = TransactionListViewModel(repo: TransactionRepository(context: container.mainContext))
    return ActivityView(context: container.mainContext, showingAddItemView: .constant(false))
        .environmentObject(vm)
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
