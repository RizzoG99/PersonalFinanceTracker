//
//  ImportResultView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

enum ImportResultFilter: Equatable {
    case all
    case new
    case duplicates
    case errors
}

struct ImportResultView: View {
    let rows: [MappedRow]
    /// Needed because `TransactionInput.category` holds the raw CSV name while the app category the
    /// user chose in step 2 lives in `categoryPersistentId` — without this the icon lookup runs on
    /// "Moto"/"Spesa", misses every keyword branch, and every row draws the same default symbol.
    let availableCategories: [CategorySnapshot]
    let isImporting: Bool
    let currentStep: Int
    let totalSteps: Int
    let onConfirm: ([TransactionInput]) -> Void
    let onDone: () -> Void

    private var validTransactions: [TransactionInput] {
        rows.filter { !$0.isDuplicate }.compactMap(\.input)
    }

    private var duplicateCount: Int {
        rows.count { $0.isDuplicate }
    }

    private var duplicateRows: [MappedRow] {
        rows.filter { $0.isDuplicate }
    }

    private var errorRows: [MappedRow] {
        rows.filter { !$0.isValid }
    }

    @State private var selectedFilter: ImportResultFilter = .all

    private var filteredRows: [MappedRow] {
        switch selectedFilter {
        case .all:
            return rows
        case .new:
            return rows.filter { !$0.isDuplicate && $0.isValid }
        case .duplicates:
            return duplicateRows
        case .errors:
            return errorRows
        }
    }

    var body: some View {
        List {
            Section {
                // Spaced, and no dividers: once each cell has its own border, a divider between two
                // borders reads as a third line, and touching borders read as one segmented control.
                HStack(spacing: 12) {
                    statCellButton(
                        value: "\(rows.count)",
                        label: "Total",
                        color: .primary,
                        filter: .all,
                        isSelected: selectedFilter == .all
                    )
                    statCellButton(
                        value: "\(validTransactions.count)",
                        label: "New",
                        color: .green,
                        filter: .new,
                        isSelected: selectedFilter == .new
                    )
                    statCellButton(
                        value: "\(duplicateCount)",
                        label: "Duplicates",
                        color: duplicateCount == 0 ? .secondary : .orange,
                        filter: .duplicates,
                        isSelected: selectedFilter == .duplicates
                    )
                    statCellButton(
                        value: "\(errorRows.count)",
                        label: "Errors",
                        color: errorRows.isEmpty ? .secondary : .red,
                        filter: .errors,
                        isSelected: selectedFilter == .errors
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                if duplicateCount > 0 && selectedFilter == .all {
                    // ponytail: "transaction is"/"transactions are" plural handled by the catalog's plural variation
                    Text("\(duplicateCount) transaction already in the app and will be skipped.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .appFormSectionBackground()

            if filteredRows.isEmpty {
                Section {
                    ContentUnavailableView(
                        label: {
                            Text(String(localized: "No rows"))
                        },
                        description: {
                            switch selectedFilter {
                            case .all:
                                Text("No transactions to import")
                            case .new:
                                Text("No new transactions")
                            case .duplicates:
                                Text("No duplicate rows")
                            case .errors:
                                Text("No errors")
                            }
                        }
                    )
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(filteredRows.prefix(50), id: \.rowIndex) { row in
                        rowContent(for: row)
                    }
                    if filteredRows.count > 50 {
                        Text("… and \(filteredRows.count - 50) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .appFormSectionBackground()
            }
        }
        .scrollContentBackground(.hidden)
        // As in step 2: a pushed destination doesn't inherit the sheet's presentationBackground.
        .appBackground()
        .navigationTitle("Import Preview")
        // Empty in the iPad two-pane layout, where this pane isn't a step you arrive at.
        .navigationSubtitle(totalSteps > 0 ? "Step \(currentStep) of \(totalSteps)" : "")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
            ZStack {
                // .borderedProminent + .tint(.accentIndigo) is the app's primary button (see the
                // Add Transaction button in DailyLoggingHabitCard). The hand-rolled fill this
                // replaces had its own corner radius, used accentColor instead of the token, and
                // had no pressed or disabled state — the disabled look was a manual grey fill.
                if validTransactions.isEmpty && !isImporting {
                    // Nothing to import (e.g. every row was a duplicate) — let
                    // the user finish instead of staring at a dead-end button.
                    Button("Done") { onDone() }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                } else {
                    Button {
                        onConfirm(validTransactions)
                    } label: {
                        if isImporting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Importing…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Import \(validTransactions.count) Transactions")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .disabled(isImporting)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentIndigo)
            .controlSize(.large)
            // On screen, not in .help(): a tooltip needs a pointer, so touch users — most of them —
            // would never have seen it. There is genuinely no undo for a batch import
            // (confirmImport calls repo.addBatch directly; the undo banner only covers deletes).
            if !isImporting && !validTransactions.isEmpty {
                Text("This can't be undone.")
                    .font(.caption2)
                    .foregroundStyle(.textDim)
            }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)
            // A fade instead of a material slab: the bar read as a grey panel bolted under the
            // button, and all this needs to do is stop rows colliding with it as they scroll past.
            .background {
                LinearGradient(
                    colors: [Color.bg0.opacity(0), Color.bg0.opacity(0.92), Color.bg0],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
        }
    }

    private func statCellButton(
        value: String,
        label: LocalizedStringKey,
        color: Color,
        filter: ImportResultFilter,
        isSelected: Bool
    ) -> some View {
        Button {
            selectedFilter = filter
        } label: {
            VStack(spacing: 4) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            // Borrowed from FilterChipsView, the app's existing filter idiom: a hairline border says
            // "control" even when unselected, an accent border says "this one is on". Dimming alone
            // said neither — it just looked like three faded labels.
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentIndigo.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.accentIndigo : Color.textPrimary.opacity(0.22),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        // No explicit accessibilityLabel: `.combine` already reads the count and its label as one
        // element, and interpolating a LocalizedStringKey into another key produced a key that no
        // catalogue entry can ever match.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func rowContent(for row: MappedRow) -> some View {
        Group {
            if let input = row.input {
                transactionRow(input)
            } else {
                errorRow(row)
            }
        }
    }

    private func errorRow(_ row: MappedRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Row \(row.rowIndex + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(row.error ?? String(localized: "Unknown error"))
                .font(.caption)
                .foregroundStyle(Color.negative)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // ponytail: was manually interpolating the raw Decimal (unlocalized description, wrong decimal
    // separator outside en-US) — formattedEUR(currency:) handles locale + currency correctly.
    private func formattedSignedAmount(_ amount: Decimal, currencyCode: String) -> String {
        let magnitude = amount.formattedEUR(currency: currencyCode)
        return amount >= 0 ? "+\(magnitude)" : magnitude
    }

    private var categoryByPersistentId: [PersistentIdentifier: CategorySnapshot] {
        Dictionary(uniqueKeysWithValues: availableCategories.map { ($0.persistentId, $0) })
    }

    private func transactionRow(_ t: TransactionInput) -> some View {
        // Prefer the app category the user mapped this row to; fall back to the CSV name only for
        // rows headed for a brand-new category, where there is nothing else to go on.
        let mapped = t.categoryPersistentId.flatMap { categoryByPersistentId[$0] }
        let symbol = mapped?.systemImage ?? CategoryInfo.info(for: t.category).symbol
        let tint = mapped.map { Color(categoryToken: $0.colorToken) }
            ?? CategoryInfo.info(for: t.category).color
        return HStack(spacing: 12) {
            GlassCard(tint: tint.opacity(0.12), borderRadius: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16, height: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(t.category.removingLeadingEmoji.localizedCategoryDisplay)
                    .font(.subheadline)
                if !t.note.isEmpty {
                    Text(t.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedSignedAmount(t.amount, currencyCode: t.currencyCode))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(t.amount >= 0 ? .positive : .negative)
                    .privacyBlur()
                Text(t.timestamp, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}
