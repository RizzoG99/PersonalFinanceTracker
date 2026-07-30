//
//  FilterChipsView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct FilterChipsView: View {
    @Environment(TransactionListViewModel.self) private var vm
    @State private var showAmountSheet = false
    @State private var showCustomDateSheet = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                typeChip
                categoryChip
                dateChip
                amountChip
            }
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showAmountSheet) {
            AmountFilterSheet().environment(vm)
        }
        .sheet(isPresented: $showCustomDateSheet) {
            CustomDateRangeSheet().environment(vm)
        }
    }

    // MARK: - Chips

    /// Category filtering only makes sense once a Type is chosen — "All" mixes income and expense categories
    private var categoryPickerEnabled: Bool { vm.filters.type != .all }

    @ViewBuilder
    private var categoryChip: some View {
        if let selected = vm.effectiveCategory {
            Button {
                vm.selectedCategory = nil
            } label: {
                chip(selected.removingLeadingEmoji.localizedCategoryDisplay, isActive: true)
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                ForEach(vm.filterCategories, id: \.self) { category in
                    Button {
                        vm.selectedCategory = category
                    } label: {
                        Label(category.removingLeadingEmoji.localizedCategoryDisplay, systemImage: CategoryInfo.info(for: category).symbol)
                    }
                }
            } label: {
                chip(String(localized: "Category"), isActive: false)
                    .opacity(categoryPickerEnabled ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!categoryPickerEnabled)
        }
    }

    @ViewBuilder
    private var typeChip: some View {
        if vm.filters.type != .all {
            Button {
                vm.filters.type = .all
                vm.selectedCategory = nil
            } label: {
                chip(String(localized: String.LocalizationValue(vm.filters.type.rawValue)), isActive: true)
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                Button("Income") { vm.filters.type = .income }
                Button("Expense") { vm.filters.type = .expense }
            } label: {
                chip(String(localized: "Type"), isActive: false)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var dateChip: some View {
        if let dr = vm.filters.dateRange {
            Button {
                vm.filters.dateRange = nil
            } label: {
                chip(dr.label, isActive: true)
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                Button("This month") { vm.filters.dateRange = .thisMonth }
                Button("Last 3 months") { vm.filters.dateRange = .last3Months }
                Button("This year") { vm.filters.dateRange = .thisYear }
                Divider()
                Button("Custom…") { showCustomDateSheet = true }
            } label: {
                chip(String(localized: "Date"), isActive: false)
            }
            .buttonStyle(.plain)
        }
    }

    private var amountChip: some View {
        Button { showAmountSheet = true } label: {
            chip(amountLabel, isActive: vm.filters.amountMin != nil || vm.filters.amountMax != nil)
        }
        .buttonStyle(.plain)
    }

    private var amountLabel: String {
        switch (vm.filters.amountMin, vm.filters.amountMax) {
        case (.some(let min), .some(let max)): return "€\(min)–€\(max)"
        case (.some(let min), nil): return "≥€\(min)"
        case (nil, .some(let max)): return "≤€\(max)"
        case (nil, nil): return String(localized: "Amount")
        }
    }

    private func chip(_ label: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
            Image(systemName: isActive ? "xmark" : "chevron.down")
                .font(isActive ? .caption2.weight(.bold) : .caption2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isActive ? Color.accentIndigo : Color.clear)
        .foregroundStyle(isActive ? Color.bg0 : Color.textPrimary)
        .clipShape(.rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isActive ? Color.clear : Color.textPrimary.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Custom Date Range Sheet

private struct CustomDateRangeSheet: View {
    @Environment(TransactionListViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var to = Date.now

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $from, displayedComponents: .date)
                DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        vm.filters.dateRange = .custom(from: from, to: to)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if case .custom(let f, let t) = vm.filters.dateRange {
                    from = f; to = t
                }
            }
        }
    }
}
