//
//  CSVColumnMappingView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CSVColumnMappingView: View {
    let file: CSVFile
    @Binding var mapping: ColumnMapping
    let currentStep: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onCancel: () -> Void

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

    private var dateFormatCheckMessage: String {
        guard let dateCol = mapping.dateColumn,
              let preview = file.preview(maxRows: 1).first,
              let colIdx = file.headers.firstIndex(of: dateCol),
              colIdx < preview.count else {
            return "Select a Date column to preview"
        }
        let dateString = preview[colIdx]
        let formatter = DateFormatter()
        formatter.dateFormat = mapping.dateFormat
        if let _ = formatter.date(from: dateString) {
            // Try to format back for display
            if let parsed = formatter.date(from: dateString) {
                let display = parsed.formatted(.dateTime.month(.abbreviated).day().year())
                return "✓ \(dateString) → \(display)"
            }
            return "✓ \(dateString) parsed successfully"
        } else {
            return "✗ Cannot parse '\(dateString)' with this format"
        }
    }

    var body: some View {
        List {
            Section("Preview") {
                ScrollView(.horizontal, showsIndicators: false) {
                    previewTable
                        .padding(.vertical, 4)
                }
            }
            .appFormSectionBackground()

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
            .appFormSectionBackground()

            Section("Optional") {
                optionalPicker(title: "Type", keyPath: \.typeColumn)
                optionalPicker(title: "Category", keyPath: \.categoryColumn)
                optionalPicker(title: "Note / Description", keyPath: \.noteColumn)
                optionalPicker(title: "Currency", keyPath: \.currencyColumn)
            }
            .appFormSectionBackground()

            // Show sign convention picker only when Type column is not mapped
            if mapping.typeColumn == nil {
                Section {
                    Picker("Sign Convention", selection: $mapping.signConvention) {
                        ForEach(SignConvention.allCases, id: \.self) { convention in
                            Text(convention.rawValue).tag(convention)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Amount Sign")
                } footer: {
                    Text("Specify how to interpret amount signs when no Type column is mapped.")
                }
                .appFormSectionBackground()
            }

            Section {
                Picker("Preset", selection: $mapping.dateFormat) {
                    ForEach(commonDateFormats, id: \.self) { fmt in
                        Text(fmt).tag(fmt)
                    }
                    // Show "Custom" option when current format is not in presets
                    if !commonDateFormats.contains(mapping.dateFormat) {
                        Divider()
                        Text("Custom").tag(mapping.dateFormat)
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
                Text(dateFormatCheckMessage)
                    .foregroundStyle(dateFormatCheckMessage.starts(with: "✗") ? .red : .secondary)
            }
            .appFormSectionBackground()
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Map Columns")
        .navigationSubtitle("Step \(currentStep) of \(totalSteps)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { onCancel() }
                    .foregroundStyle(.red)
            }
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

    // ponytail: hard cap so a malformed file (e.g. thousands of parsed "columns")
    // can never freeze this non-lazy HStack
    private static let previewColumnCap = 30

    @ViewBuilder
    private var previewTable: some View {
        let previewRows = file.preview(maxRows: 3)
        let shownColumns = min(file.headers.count, Self.previewColumnCap)
        if previewRows.isEmpty {
            Text("No data rows")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(file.headers.prefix(shownColumns), id: \.self) { header in
                        Text(header)
                            .font(.caption.bold())
                            .lineLimit(1)
                            .frame(width: 110, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray5))
                    }
                    if file.headers.count > shownColumns {
                        Text("… +\(file.headers.count - shownColumns) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                    }
                }

                Divider()

                ForEach(previewRows.indices, id: \.self) { rowIdx in
                    HStack(spacing: 0) {
                        ForEach(0..<shownColumns, id: \.self) { colIdx in
                            let val = colIdx < previewRows[rowIdx].count ? String(previewRows[rowIdx][colIdx].prefix(80)) : ""
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
