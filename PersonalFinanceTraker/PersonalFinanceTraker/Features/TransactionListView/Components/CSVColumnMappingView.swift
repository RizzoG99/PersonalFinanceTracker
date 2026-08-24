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
    /// False when hosted in the iPad two-pane layout, which owns Cancel and has no "next step" —
    /// the preview pane updates as you map, so there is nothing to advance to.
    var showsStepActions: Bool = true

    /// See ImportResultView.barTitle — every pane embedded in the iPad sheet's one bar must
    /// agree on the title.
    private var barTitle: LocalizedStringKey {
        showsStepActions ? "Map Columns" : "Import"
    }

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

    /// A value rather than a pre-formatted string: the previous version decided validity by
    /// testing whether the message started with "✗", which any translation would have broken —
    /// and it wrapped interpolated text in `String(localized:)`, which can never match a
    /// catalogue key, so those messages were untranslatable anyway.
    private enum DateFormatCheck {
        case needsColumn
        case parsed(raw: String, display: String)
        case failed(raw: String)
    }

    private var dateFormatCheck: DateFormatCheck {
        guard let dateCol = mapping.dateColumn,
              let preview = file.preview(maxRows: 1).first,
              let colIdx = file.headers.firstIndex(of: dateCol),
              colIdx < preview.count else {
            return .needsColumn
        }
        let dateString = preview[colIdx]
        let formatter = DateFormatter()
        formatter.dateFormat = mapping.dateFormat
        guard let parsed = formatter.date(from: dateString) else {
            return .failed(raw: dateString)
        }
        return .parsed(
            raw: dateString,
            display: parsed.formatted(.dateTime.month(.abbreviated).day().year())
        )
    }

    /// SF Symbols plus text, not a ✓/✗ glyph: validity must not rest on colour or on a
    /// character a screen reader reads as "check mark" (WCAG 1.4.1).
    @ViewBuilder
    private var dateFormatFooter: some View {
        switch dateFormatCheck {
        case .needsColumn:
            Text("Select a Date column to preview")
                .foregroundStyle(.secondary)
        case let .parsed(raw, display):
            Label {
                Text("Valid format — \(raw) reads as \(display)")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .foregroundStyle(.secondary)
        case let .failed(raw):
            Label {
                Text("Invalid format — can't read \(raw)")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(Color.negative)
        }
    }

    private var canContinueBanner: some View {
        Label {
            Text("Map Date and Amount to continue.")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.footnote)
        .foregroundStyle(Color.negative)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    var body: some View {
        List {
            Section("Preview") {
                ScrollView(.horizontal) {
                    previewTable
                        .padding(.vertical, 4)
                        // Zero row insets gave the table the full card width but left the first
                        // column's text flush against the card's edge.
                        .padding(.horizontal, 14)
                }
                // A file like the user's has 11 columns and only 3 fit, with nothing on screen
                // saying so. The flash on appear is the affordance; .visible alone would fade
                // before anyone looked at it.
                .scrollIndicators(.visible)
                .scrollIndicatorsFlash(onAppear: true)
                // The preview is the reason this step exists, so it gets the full sheet width —
                // the default row insets were costing it about a column and a half on iPad.
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            .appFormSectionBackground()

            Section {
                requiredPicker(title: "Date", keyPath: \.dateColumn)
                requiredPicker(title: "Amount", keyPath: \.amountColumn)
            } header: {
                Text("Required")
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
                            Text(String(localized: String.LocalizationValue(convention.rawValue))).tag(convention)
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
                    Spacer()
                    TextField("e.g. yyyy-MM-dd", text: $mapping.dateFormat)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.subheadline, design: .monospaced))
                        .frame(maxWidth: 200)
                }
            } header: {
                Text("Date Format")
            } footer: {
                dateFormatFooter
            }
            .appFormSectionBackground()
        }
        // Capped on the List, not per Section: a frame on a Section doesn't reach the rows — the
        // List lays those out itself — so per-section caps just detach headers from their content.
        // 900 rather than the 640 default because this screen has to serve both a form and a wide
        // table; it keeps label-to-value travel sane without starving the preview of columns.
        .readableWidth(900)
        .scrollContentBackground(.hidden)
        // Pinned rather than left as the Required section's footer: that footer scrolls away, so
        // the disabled Continue button ends up with no explanation anywhere on screen.
        .safeAreaInset(edge: .bottom) {
            if !canContinue {
                canContinueBanner
            }
        }
        .navigationTitle(barTitle)
        .navigationSubtitle(showsStepActions ? "Step \(currentStep) of \(totalSteps)" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsStepActions {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Continue") { onContinue() }
                        .bold()
                        .disabled(!canContinue)
                }
            }
        }
    }

    // MARK: - Pickers

    @ViewBuilder
    private func requiredPicker(title: LocalizedStringKey, keyPath: WritableKeyPath<ColumnMapping, String?>) -> some View {
        Picker(title, selection: requiredBinding(keyPath)) {
            ForEach(Array(columnOptions.enumerated()), id: \.offset) { _, col in
                columnOptionText(col).tag(col)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func optionalPicker(title: LocalizedStringKey, keyPath: WritableKeyPath<ColumnMapping, String?>) -> some View {
        Picker(title, selection: optionalBinding(keyPath)) {
            ForEach(Array(columnOptions.enumerated()), id: \.offset) { _, col in
                columnOptionText(col).tag(col)
            }
        }
        .pickerStyle(.menu)
    }

    /// CSV headers are user data and must stay verbatim; only the "(None)" sentinel is app UI text.
    private func columnOptionText(_ col: String) -> Text {
        col == noneOption ? Text("(None)") : Text(col)
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

    /// "Row 1. Period: 21/05/2026. Accounts: Buddybank." — headers paired with their values, so a
    /// screen-reader user can tell what they are mapping.
    private func rowLabel(_ row: [String], headers: [String], index: Int) -> String {
        let pairs = headers.enumerated().map { offset, header in
            let value = offset < row.count && !row[offset].isEmpty ? row[offset] : String(localized: "empty")
            return "\(header): \(value)"
        }
        // Interpolating into the key is what broke the date-format messages; keep the key literal.
        let rowNumber = "\(String(localized: "Row")) \(index + 1)"
        return ([rowNumber] + pairs).joined(separator: ". ")
    }

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
            let headers = Array(file.headers.prefix(shownColumns))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(headers, id: \.self) { header in
                        Text(header)
                            .font(.caption.bold())
                            .lineLimit(1)
                            .frame(width: 110, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .background(Color.bg2)
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
                                .background(rowIdx % 2 == 0 ? Color.clear : Color.bg1)
                        }
                    }
                    // One utterance per row, paired header-to-value. Left as loose cells VoiceOver
                    // reads a column of values with nothing saying which column they came from.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(rowLabel(previewRows[rowIdx], headers: headers, index: rowIdx))
                    if rowIdx < previewRows.count - 1 { Divider() }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.hairline, lineWidth: 0.5)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("File preview, first \(previewRows.count) rows")
        }
    }
}
