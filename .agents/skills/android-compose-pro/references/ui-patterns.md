# Android UI patterns

## States and feedback

Model meaningful UI states explicitly. Loading names the work without fake progress; first-run
empty states explain the value and give one action; no-results states preserve search/filter
context and offer a reset; errors state what failed and provide a real recovery action.

Use inline validation for fields, `SnackbarHost` for brief success or undo, and `AlertDialog` for
blocking or destructive decisions. Do not present an error as an empty state.

## Financial values

- Format money through shared formatters or a dedicated formatter, never string interpolation.
- Keep signs explicit. Use `BigDecimal` until display/chart boundaries.
- Use stable, readable digit typography for comparable totals or rows. Values must wrap or adapt,
  never silently truncate.
- Apply privacy treatment consistently once Android privacy settings exist; do not hide a value
  visually while leaving it readable by TalkBack.

## Search, filters, and navigation

- Search matches text; filters narrow structured constraints; sorting changes order. Keep them
  independently reversible.
- Surface active constraints and offer a clear path. Distinguish an empty ledger from no results.
- Keep one primary action per screen. Put current-screen actions in the top app bar or a clearly
  scoped floating action button; navigation belongs in the app shell.
- Use native modal bottom sheets for focused, dismissible tasks. Prefer navigation for a drill-in
  flow. Do not use a sheet to conceal a multi-step destination.

## Editing and destructive actions

- Use visible labels or accessible content descriptions for every icon action.
- Disable a commit action until input is valid; show validation near the field.
- Confirm destructive actions proportionally and preserve undo when the domain supports it.
- Keep keyboard focus, scrolling, dismissal, and Back behavior conventional for Android.
