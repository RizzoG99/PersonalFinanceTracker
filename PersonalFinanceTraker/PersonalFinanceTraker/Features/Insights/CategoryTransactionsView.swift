import SwiftUI

/// A category row's drill-down from the Insights explorer: that category's transactions for the
/// explorer's period and type, grouped by day like Activity, under a summary of what the row
/// said (total, how many, which period). Rows come from `CompassViewModel` on every render (not
/// a list captured at tap time), so an edit saved from here — which reloads the model — shows.
struct CategoryTransactionsView: View {
    let drillDown: ExplorerDrillDown
    let viewModel: CompassViewModel
    @Environment(TransactionListViewModel.self) private var transactionListViewModel

    private var items: [TransactionSnapshot] {
        viewModel.transactions(inCategory: drillDown.category, interval: drillDown.interval, dataType: drillDown.dataType)
    }

    private var title: String { drillDown.category.removingLeadingEmoji.localizedCategoryDisplay }

    var body: some View {
        let items = items
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No transactions",
                    systemImage: "tray",
                    description: Text("Nothing left in this category for \(drillDown.periodLabel).")
                )
            } else {
                List {
                    Section {
                        summary(items)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listSectionSeparator(.hidden)

                    // Same day grouping and headers ("Today", "Yesterday", "Mon 14 Sep") as
                    // Activity, so this reads as a filtered slice of that list.
                    ForEach(Self.groupedByDay(items), id: \.day) { group in
                        Section {
                            ForEach(group.items) { item in
                                Button {
                                    transactionListViewModel.transactionToEdit = item
                                } label: {
                                    TransactionItemView(
                                        item: item,
                                        showsTravelBadge: true,
                                        travel: transactionListViewModel.travel(for: item)
                                    )
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                            }
                        } header: {
                            Text(group.day.formattedForTransaction())
                                .font(.headline)
                                .foregroundStyle(.textPrimary)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
    }

    /// What the explorer row said, restated: total for the period, how many transactions, and
    /// which period and type — so the list makes sense on its own.
    private func summary(_ items: [TransactionSnapshot]) -> some View {
        let total = PieChartDataService().categoryTotals(items)[drillDown.category] ?? 0
        let kind = drillDown.dataType == .income ? String(localized: "Income") : String(localized: "Expenses")
        return GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(kind) · \(drillDown.periodLabel)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.textDim)
                Text(total.formattedEUR())
                    .font(.title2.bold())
                    .foregroundStyle(.textPrimary)
                    .privacyBlur()
                Text("\(items.count) transactions")
                    .font(.subheadline)
                    .foregroundStyle(.textMid)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    struct DayGroup {
        let day: Date
        let items: [TransactionSnapshot]
    }

    /// Newest day first, newest transaction first within a day.
    static func groupedByDay(_ items: [TransactionSnapshot], calendar: Calendar = .current) -> [DayGroup] {
        Dictionary(grouping: items) { calendar.startOfDay(for: $0.timestamp) }
            .sorted { $0.key > $1.key }
            .map { DayGroup(day: $0.key, items: $0.value.sorted { $0.timestamp > $1.timestamp }) }
    }
}
