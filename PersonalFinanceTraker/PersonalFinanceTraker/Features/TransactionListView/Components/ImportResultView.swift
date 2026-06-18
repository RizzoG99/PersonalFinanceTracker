//
//  ImportResultView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct ImportResultView: View {
    let rows: [MappedRow]
    let onConfirm: ([TransactionModel]) -> Void

    private var validTransactions: [TransactionModel] {
        rows.compactMap(\.transaction)
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
                    statCell(value: "\(validTransactions.count)", label: "Valid", color: .green)
                    Divider()
                    statCell(value: "\(errors.count)", label: "Errors", color: errors.isEmpty ? .secondary : .red)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

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
            }
        }
        .navigationTitle("Import Preview")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                onConfirm(validTransactions)
            } label: {
                Text("Import \(validTransactions.count) Transactions")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(validTransactions.isEmpty ? Color(.systemGray4) : Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(validTransactions.isEmpty)
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

    private func transactionRow(_ t: TransactionModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.category)
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
