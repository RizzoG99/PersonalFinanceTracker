# Feature: Import Transactions from Excel

## Problem
Users have transaction history in `.xlsx` spreadsheets (bank exports, other finance
apps) and currently can only import via CSV.

## Approach
Add an `.xlsx` reader using the **CoreXLSX** SPM package (transitively pulls in
ZIPFoundation), then adapt its parsed sheet into the existing `CSVFile` value type.
Everything downstream — `CSVColumnMapper.autoDetect`, `CSVColumnMappingView`,
`CSVCategoryMappingView`, duplicate detection — is reused unchanged. This keeps new
code to the file-format boundary only, avoiding a second mapping/UI pipeline.

## Key decisions
- Reuse, don't fork: XLSX rows get converted to `CSVFile` (headers + `[[String]]`
  rows) so `CSVColumnMapper.autoDetect` and the two mapping screens work as-is —
  same auto-detect keyword lists, same "ask only when unsure" UX as CSV import.
- New dependency: this is the app's first SPM dependency (CoreXLSX +
  ZIPFoundation transitively). No dependency does this today because CSV parsing is
  hand-rolled.
- Only the first sheet is read for v1 — multi-sheet workbook selection is
  out of scope (YAGNI) unless real files need it.
- Numeric/date cells in XLSX are typed (not plain strings like CSV). The adapter
  must stringify Excel serial dates and numbers before handing rows to
  `CSVColumnMapper`, or auto-detect's date-format inference will break.

## Architecture notes
- **Add dependency**: CoreXLSX via SPM in `PersonalFinanceTraker.xcodeproj`.
- **New file**: `Utilities/XLSXFile.swift` — thin adapter: `XLSXFile.read(from:) throws -> CSVFile`
  (parses workbook, first worksheet, shared strings; converts each row's cells to
  strings, converting Excel date serials to the same string format `CSVColumnMapper`
  expects).
- **Modify**: `Features/Profile/Views/ProfileView.swift` — extend the `fileImporter`
  `allowedContentTypes` to include `.xlsx` (`UTType(filenameExtension: "xlsx")` or
  `.spreadsheet` if available), and branch on file extension before calling
  `transactionViewModel.loadCSVFile` vs. a new `loadExcelFile`.
- **Modify**: `TransactionListViewModel.swift` — add `loadExcelFile(from:)` that
  calls `XLSXFile.read`, converts to `CSVFile`, and otherwise follows the same path
  as `loadCSVFile`.
- No SwiftData schema changes.

## Where to start
Add the CoreXLSX SPM dependency, then write `XLSXFile.read(from:) -> CSVFile` and a
throwaway one-file self-check confirming it produces the same headers/rows shape
`CSVColumnMapper` expects from a small sample `.xlsx`.
