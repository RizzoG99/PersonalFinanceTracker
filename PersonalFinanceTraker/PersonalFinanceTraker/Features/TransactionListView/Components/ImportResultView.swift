//
//  ImportResultView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct ImportResultView: View {
    let rows: [MappedRow]
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

    private var errors: [MappedRow] {
        rows.filter { !$0.isValid }
    }

    @State private var showErrors = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    statCell(value: "\(rows.count)", label: "Total", color: .primary)
                    Divider()
                    statCell(value: "\(validTransactions.count)", label: "New", color: .green)
                    Divider()
                    statCell(value: "\(duplicateCount)", label: "Duplicates", color: duplicateCount == 0 ? .secondary : .orange)
                    Divider()
                    statCell(value: "\(errors.count)", label: "Errors", color: errors.isEmpty ? .secondary : .red)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                if duplicateCount > 0 {
                    Text("\(duplicateCount) transaction\(duplicateCount == 1 ? " is" : "s are") already in the app and will be skipped.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .appFormSectionBackground()

            if !validTransactions.isEmpty {
                Section("To Import (\(validTransactions.count))") {
                    ForEach(validTransactions.prefix(50).indices, id: \.self) { i in
                        transactionRow(validTransactions[i])
                    }
                    if validTransactions.count > 50 {
                        Text("… and \(validTransactions.count - 50) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .appFormSectionBackground()
            }

            if !errors.isEmpty {
                Section(isExpanded: $showErrors) {
                    ForEach(errors, id: \.rowIndex) { row in
                        Text(row.error ?? "Unknown error")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    HStack {
                        Text("Errors (\(errors.count))")
                        Spacer()
                        Button(showErrors ? "Hide" : "Show") { showErrors.toggle() }
                            .font(.caption)
                    }
                }
                .appFormSectionBackground()
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Import Preview")
        .navigationSubtitle("Step \(currentStep) of \(totalSteps)")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            ZStack {
                if validTransactions.isEmpty && !isImporting {
                    // Nothing to import (e.g. every row was a duplicate) — let
                    // the user finish instead of staring at a dead-end button.
                    Button {
                        onDone()
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Button {
                        onConfirm(validTransactions)
                    } label: {
                        if isImporting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                                Text("Importing…")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            Text("Import \(validTransactions.count) Transactions")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(isImporting ? Color(.systemGray4) : Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isImporting)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func transactionRow(_ t: TransactionInput) -> some View {
        HStack {
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
                Text("\(t.amount >= 0 ? "+" : "")\(t.amount) \(t.currencyCode)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(t.amount >= 0 ? .green : .red)
                Text(t.timestamp, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
