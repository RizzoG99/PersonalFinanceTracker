//
//  CSVColumnMappingView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CSVColumnMappingView: View {
    let file: CSVFile
    @Binding var mapping: ColumnMapping
    let onContinue: () -> Void

    private let noneOption = "(None)"

    private let commonDateFormats = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
        "dd/MM/yyyy",
        "MM/dd/yyyy",
        "dd-MM-yyyy"
    ]

    private var columnOptions: [String] { [noneOption] + file.headers }

    private var canContinue: Bool {
        mapping.dateColumn != nil && mapping.amountColumn != nil
    }

    var body: some View {
        List {
            Section("Preview") {
                ScrollView(.horizontal, showsIndicators: false) {
                    previewTable
                        .padding(.vertical, 4)
                }
            }

            Section {
                requiredPicker(title: "Date", keyPath: \.dateColumn)
                requiredPicker(title: "Amount", keyPath: \.amountColumn)
            } header: {
                Text("Required")
            } footer: {
                if !canContinue {
                    Text("Map Date and Amount to continue.")
                        .foregroundStyle(.red)
                }
            }

            Section("Optional") {
                optionalPicker(title: "Type", keyPath: \.typeColumn)
                optionalPicker(title: "Category", keyPath: \.categoryColumn)
                optionalPicker(title: "Note / Description", keyPath: \.noteColumn)
                optionalPicker(title: "Currency", keyPath: \.currencyColumn)
            }

            Section {
                Picker("Preset", selection: $mapping.dateFormat) {
                    ForEach(commonDateFormats, id: \.self) { fmt in
                        Text(fmt).tag(fmt)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Format")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("e.g. yyyy-MM-dd", text: $mapping.dateFormat)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.subheadline, design: .monospaced))
                        .frame(maxWidth: 200)
                }
            } header: {
                Text("Date Format")
            } footer: {
                Text("Edit the format string directly if none of the presets match your CSV.")
            }
        }
        .navigationTitle("Map Columns")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Continue") { onContinue() }
                    .bold()
                    .disabled(!canContinue)
            }
        }
    }

    // MARK: - Pickers

    @ViewBuilder
    private func requiredPicker(title: String, keyPath: WritableKeyPath<ColumnMapping, String?>) -> some View {
        Picker(title, selection: requiredBinding(keyPath)) {
            ForEach(Array(columnOptions.enumerated()), id: \.offset) { _, col in
                Text(col).tag(col)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func optionalPicker(title: String, keyPath: WritableKeyPath<ColumnMapping, String?>) -> some View {
        Picker(title, selection: optionalBinding(keyPath)) {
            ForEach(Array(columnOptions.enumerated()), id: \.offset) { _, col in
                Text(col).tag(col)
            }
        }
        .pickerStyle(.menu)
    }

    private func requiredBinding(_ keyPath: WritableKeyPath<ColumnMapping, String?>) -> Binding<String> {
        Binding(
            get: { mapping[keyPath: keyPath] ?? noneOption },
            set: { mapping[keyPath: keyPath] = $0 == noneOption ? nil : $0 }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<ColumnMapping, String?>) -> Binding<String> {
        requiredBinding(keyPath)
    }

    // MARK: - Preview Table

    @ViewBuilder
    private var previewTable: some View {
        let previewRows = file.preview(maxRows: 3)
        if previewRows.isEmpty {
            Text("No data rows")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(file.headers, id: \.self) { header in
                        Text(header)
                            .font(.caption.bold())
                            .frame(width: 110, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray5))
                    }
                }

                Divider()

                ForEach(previewRows.indices, id: \.self) { rowIdx in
                    HStack(spacing: 0) {
                        ForEach(0..<file.headers.count, id: \.self) { colIdx in
                            let val = colIdx < previewRows[rowIdx].count ? previewRows[rowIdx][colIdx] : ""
                            Text(val.isEmpty ? "—" : val)
                                .font(.caption)
                                .foregroundStyle(val.isEmpty ? .tertiary : .primary)
                                .lineLimit(1)
                                .frame(width: 110, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
                                .background(rowIdx % 2 == 0 ? Color.clear : Color(.systemGray6))
                        }
                    }
                    if rowIdx < previewRows.count - 1 { Divider() }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.systemGray4), lineWidth: 0.5)
            )
        }
    }
}
