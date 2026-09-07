//
//  TravelDetailSheet.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// The inside of a travel folder: what the trip cost, what is in it, and the fastest
/// way to add the next expense while you are still on the trip.
struct TravelDetailSheet: View {
    let travel: TravelSummary
    let members: [TransactionSnapshot]

    let onAddExpense: () -> Void
    let onSelect: (TransactionSnapshot) -> Void
    let onRename: (String, String) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_base_currency") private var currencyCode = "EUR"

    @State private var showingRename = false
    @State private var showingDeleteConfirmation = false

    private var countLabel: String { TravelCountLabel.text(members.count) }

    private var report: TravelReport { TravelReport(members: members) }

    private var dateRangeText: String? {
        guard let start = report.startDate, let end = report.endDate else { return nil }
        return start.formatted(date: .abbreviated, time: .omitted)
            == end.formatted(date: .abbreviated, time: .omitted)
            ? start.formatted(date: .abbreviated, time: .omitted)
            : "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    totalCard
                    if report.count > 0 {
                        tripStats
                        categoryBreakdown
                    }
                    addExpenseButton
                    memberSection
                }
                .padding(24)
                .readableWidth()
            }
            .appBackground()
            .navigationTitle(travel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rename", systemImage: "pencil") { showingRename = true }
                        Button("Delete Travel", systemImage: "trash", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    } label: {
                        Label("Travel options", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingRename) {
                TravelFormSheet(name: travel.name, symbolName: travel.symbolName, isEditing: true, onSave: onRename)
            }
            // The folder is destructive, its contents are not — the message has to say so,
            // or "Delete" reads as "delete €400 of history".
            .confirmationDialog(
                "Delete \(travel.name)?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Travel", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The \(countLabel) inside stay in your transactions — only the travel is removed.")
            }
        }
    }

    private var totalCard: some View {
        GlassCard {
            VStack(spacing: 8) {
                Text("Total")
                    .font(.subheadline)
                    .foregroundStyle(.textDim)
                Text(
                    travel.total,
                    format: .currency(code: currencyCode)
                        .sign(strategy: travel.total == 0 ? .never : .always())
                )
                    .font(.title.bold())
                    .foregroundStyle(travel.total == 0 ? Color.textMid : (travel.total > 0 ? .positive : .negative))
                    .privacyBlur()
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
    }

    /// When the trip happened, how long it lasted, and what a day of it cost.
    private var tripStats: some View {
        GlassCard {
            VStack(spacing: 12) {
                if let dateRangeText {
                    statRow(String(localized: "Dates"), Text(dateRangeText))
                    Divider().overlay(Color.hairline)
                }
                statRow(
                    String(localized: "Duration"),
                    Text(TravelCountLabel.days(report.dayCount))
                )
                Divider().overlay(Color.hairline)
                statRow(
                    String(localized: "Per day"),
                    Text(report.perDay, format: .currency(code: currencyCode)).privacyBlur()
                )
                // Only worth a row when something was actually paid back — otherwise it
                // is a permanent "0,00 €" that means nothing.
                if report.refunded > 0 {
                    Divider().overlay(Color.hairline)
                    statRow(
                        String(localized: "Refunded"),
                        Text(report.refunded, format: .currency(code: currencyCode))
                            .foregroundStyle(.positive)
                            .privacyBlur()
                    )
                }
            }
        }
    }

    private func statRow(_ label: String, _ value: some View) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.textDim)
            Spacer()
            value
                .font(.subheadline.bold())
                .foregroundStyle(.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Where the money went. A bar per category rather than a pie: this is a ranking,
    /// and bars stay readable at accessibility text sizes where a pie's labels do not.
    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where it went")
                .font(.subheadline)
                .foregroundStyle(.textDim)

            GlassCard {
                VStack(spacing: 12) {
                    ForEach(report.categories) { entry in
                        categoryBar(entry)
                    }
                }
            }
        }
    }

    private func categoryBar(_ entry: TravelReport.CategorySpend) -> some View {
        let share = report.spent > 0
            ? Double(truncating: (entry.amount / report.spent) as NSDecimalNumber)
            : 0
        let info = CategoryInfo.info(for: entry.category)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: info.symbol)
                    .font(.caption)
                    .foregroundStyle(info.color)
                    .frame(width: 16)
                Text(entry.category.removingLeadingEmoji.localizedCategoryDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.textPrimary)
                Spacer(minLength: 8)
                Text(entry.amount, format: .currency(code: currencyCode))
                    .font(.subheadline.bold())
                    .foregroundStyle(.textPrimary)
                    .privacyBlur()
            }
            // The share is also stated in the accessibility value below, so the bar is
            // never the only way to read the proportion.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.hairline)
                    Capsule()
                        .fill(info.color)
                        .frame(width: max(2, geo.size.width * share))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("\(Int((share * 100).rounded()))%"))
    }

    // The one obvious primary action: this is why tagging can stay explicit without
    // becoming a chore — on the trip you open the travel, not the general add flow.
    private var addExpenseButton: some View {
        Button(action: onAddExpense) {
            Label("Add expense", systemImage: "plus.circle.fill")
                .font(.headline)
                .foregroundStyle(Color.primaryActionForeground)
                .frame(maxWidth: .infinity)
                .padding()
                .glassEffect(.regular.tint(Color.accentIndigo).interactive())
        }
    }

    @ViewBuilder
    private var memberSection: some View {
        if members.isEmpty {
            ContentUnavailableView(
                "No expenses yet",
                systemImage: "tray",
                description: Text("Add the first expense of this travel, or tag an existing one from its edit screen.")
            )
            .padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Expenses")
                    .font(.subheadline)
                    .foregroundStyle(.textDim)

                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, item in
                            Button {
                                onSelect(item)
                            } label: {
                                TransactionItemView(item: item)
                            }
                            .buttonStyle(.plain)

                            if index < members.count - 1 {
                                Divider().overlay(Color.hairline)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    TravelDetailSheet(
        travel: TravelSummary(
            id: UUID(), name: "Barcellona Travel", symbolName: "airplane",
            total: -400, count: 2, anchorDate: Date()
        ),
        members: [
            TransactionSnapshot(TransactionModel(timestamp: Date(), amount: -250, note: "Hotel", category: "🏨 Travel")),
            TransactionSnapshot(TransactionModel(timestamp: Date(), amount: -150, note: "Flights", category: "🏨 Travel")),
        ],
        onAddExpense: {}, onSelect: { _ in }, onRename: { _, _ in }, onDelete: {}
    )
}

#Preview("Empty") {
    TravelDetailSheet(
        travel: TravelSummary(
            id: UUID(), name: "Not started yet", symbolName: "backpack",
            total: 0, count: 0, anchorDate: Date()
        ),
        members: [],
        onAddExpense: {}, onSelect: { _ in }, onRename: { _, _ in }, onDelete: {}
    )
}
