# Design: Import Transactions from Excel

## Problem

Users have transaction history in `.xlsx` spreadsheets (bank exports, exports from
other personal-finance apps) with arbitrary, varying column layouts. Today the app
only accepts CSV. We want the same "auto-detect the format, only ask when unsure"
import experience CSV already offers, applied to `.xlsx` files.

## Approach

Add an `.xlsx` reader using the **CoreXLSX** SPM package (transitively pulls in
ZIPFoundation) — this is the app's first SPM dependency, since CSV parsing today is
entirely hand-rolled and there is no existing zip/XML reader to build on. The reader
converts a chosen worksheet into the existing `CSVFile` value type (headers +
`[[String]]` rows), so everything downstream — `CSVColumnMapper.autoDetect`,
`CSVColumnMappingView`, `CSVCategoryMappingView`, duplicate detection, category
resolution — is reused completely unchanged.

Rejected alternatives:
- **Hand-rolled ZIPFoundation + XMLParser reader** — smaller dependency footprint,
  but meaningfully more code to write and maintain for the same result.
- **Separate Excel-only mapping pipeline** — would duplicate the CSV mapping UI and
  auto-detect logic for no benefit.

## Architecture

```
ProfileView (.fileImporter, extension routing)
        │  .xlsx
        ▼
XLSXFile.read(from: url) throws -> XLSXFile   // CoreXLSX parse, exposes sheetNames
        │
        ▼ (if sheetNames.count > 1)
SheetPickerView  →  user picks a sheet
        │
        ▼
XLSXFile.csvFile(forSheet:) -> CSVFile          // cell-by-cell string conversion
        │
        ▼
   ── existing CSV pipeline, unchanged ──
CSVColumnMapper.autoDetect → CSVColumnMappingView → CSVCategoryMappingView → import
```

Only two new pieces are added: a workbook reader/adapter and a sheet picker view.
Everything from `CSVFile` onward is existing, untouched code.

## Components

**`Utilities/XLSXFile.swift`** (new)
- `XLSXFile.read(from: URL) throws -> XLSXFile` — opens the archive via CoreXLSX,
  retains the parsed workbook + shared strings table, exposes `sheetNames: [String]`.
- `func csvFile(forSheet name: String) -> CSVFile` — reads that worksheet's rows,
  converts each cell to a string per the canonical-value rule below. First row
  becomes headers. Produces the exact same shape `CSVFile.parse` produces from CSV
  text, so no changes are needed to `CSVColumnMapper` or any mapping view.
- Cell conversion rule (canonical, not display format):
  - Date-serial cells → fixed ISO string `yyyy-MM-dd HH:mm:ss` (matches
    `CSVColumnMapper`'s default `dateFormat`, so auto-detect needs no changes for
    Excel-sourced dates).
  - Numeric cells → plain decimal text, no thousands separators (e.g. `1234.56`).
  - String / shared-string cells → used as-is.
  - Empty cell → `""`.
- Any parse failure (corrupt file, password-protected, wrong format like legacy
  `.xls`) is caught and surfaced as a single `XLSXFile.ImportError.unreadable`
  case — no attempt to distinguish failure causes for v1.
- Only the sheet the user selects is read; other sheets are ignored.

**`Features/TransactionListView/Components/SheetPickerView.swift`** (new)
- A simple list of `sheetNames`, shown only when `sheetNames.count > 1`. Selecting a
  name calls `csvFile(forSheet:)` and continues into the existing
  `CSVColumnMappingView` flow.
- If the workbook has exactly one sheet, this screen is skipped entirely and the
  flow goes straight into column mapping, identical to the CSV path today.

**`Features/Profile/Views/ProfileView.swift`** (modify)
- `fileImporter(allowedContentTypes:)` gains `UTType(filenameExtension: "xlsx")!`.
- On success, branch by file extension: `.csv`/`.txt` → existing `loadCSVFile`;
  `.xlsx` → new `loadExcelFile`.

**`TransactionListViewModel.swift`** (modify)
- `loadExcelFile(from url: URL)`: calls `XLSXFile.read` off the main actor (mirrors
  how CSV mapping already keeps row-processing off `@MainActor` via
  `Task.detached`/`RawMappedRow`). On success, either shows `SheetPickerView` (multi
  sheet) or resolves the lone sheet automatically, then converts to `CSVFile` and
  feeds the same `csvFile`/`columnMapping` state `loadCSVFile` already populates —
  `CSVColumnMappingView` does not know or care whether the source was CSV or Excel.
  On failure, sets `importError` (same property CSV failures already use).

## Data flow & error handling

- Bad file (legacy `.xls`, password-protected, corrupt `.xlsx`): `XLSXFile.read`
  throws → caught in `loadExcelFile` → sets `importError` → existing error banner
  shows a single generic message (e.g. "Couldn't read this file — make sure it's an
  unprotected .xlsx"). No per-cause messaging in v1.
- Empty sheet / no header row: produces an empty/degenerate `CSVFile`, which the
  existing mapping view already handles as "no rows found" — no new handling
  required since it's the same type CSV already produces in that case.
- Everything after `CSVFile` is produced (duplicate detection, category resolution,
  sign convention, category mapping) is unmodified existing code.

## Testing

- **Unit** (`XLSXFileTests.swift`, Swift Testing):
  - Multi-sheet workbook → correct `sheetNames`.
  - Single-sheet workbook → `csvFile(forSheet:)` output matches a hand-built
    `CSVFile` (same headers/rows shape).
  - Date-serial cell → correct canonical ISO string.
  - Numeric cell → plain decimal string, no thousands separator.
  - Malformed/corrupt file → throws `XLSXFile.ImportError.unreadable`.
- **UI** (existing UI test target): file picker → sheet picker (multi-sheet
  fixture) → column mapping → import completes, mirroring the existing CSV import
  UI test.

## Out of scope (YAGNI)

- Legacy binary `.xls` support.
- Password-protected file support.
- Distinguishing error causes in the error message.
- Preserving Excel's display/number-format when converting cells (canonical value
  conversion only).
