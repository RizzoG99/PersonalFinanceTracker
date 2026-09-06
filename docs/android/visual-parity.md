# Android visual-parity baseline

This document translates the current iOS visual system into native Android rules. It is a shared
baseline for Android parity work; it does not require reproducing iOS controls pixel for pixel.

| iOS source | Android implementation | Intent |
| --- | --- | --- |
| `AppBackground` | `AppBackground` Compose component | Calm warm background with subtle indigo and teal blooms in both appearances. |
| `accentIndigo`, semantic ink and surface tokens | `PersonalFinanceTheme` Material 3 scheme and `FinancePalette` | Keep primary actions, financial semantics, surfaces, and text hierarchy consistent. |
| `GlassCard` | `FinanceCard` | Group balance, summaries, and transactions without heavy elevation. |
| Dashboard balance card | Home financial overview | Put balance first, then the current pay-cycle income and expenses. |
| iOS tab shell | Compose `NavigationBar` | Preserve Home, Activity, and Insights information architecture using Android navigation behavior. |

## Guardrails

- Feature screens use theme roles and shared components; they do not define local colors.
- Positive and negative money values use explicit signs as well as semantic color.
- Native Material controls remain native. The app mirrors iOS hierarchy and character, not iOS interaction mechanics.
- Each visual parity feature must be reviewed in light/dark appearance, compact/wide layouts, and with large localized text before it is marked matched.

## Screenshot references

Use the current iPhone captures as the parity reference, especially
`docs/screenshots/iphone/{light,dark}/01-dashboard.png` and
`docs/screenshots/iphone/{light,dark}/02-activity.png`. They describe information hierarchy,
colour relationships, and states; Android retains Material navigation, sheets, and back behaviour.

## Verification record

- 2026-09-04: Home and Activity were inspected on a Pixel 7 emulator in light and dark appearance,
  against the current iPhone dashboard and Activity captures. This covered the populated and empty
  states, shell and system bars, readable foreground colour, dashboard greeting/balance hierarchy,
  Activity search surface, and empty-state action.
- 2026-09-04: At 150% font scale, Home period statistics and Activity summary cards reflow into
  full-width rows; Activity transaction actions remain reachable. Activity was also checked in
  landscape: Add moves to the top bar so it does not cover the financial summary, and the portrait
  list reserves space for the floating action button.
- 2026-09-04: Activity interaction QA passed for a no-results search and its recovery action, the
  filter sheet and custom-date dialog, keyboard dismissal followed by sheet dismissal using Back,
  and the delete confirmation plus Undo. The latter used and restored an emulator-only sample
  transaction.
- 2026-09-04: Italian app-locale inspection covered Home, Activity, and the filter sheet. Long
  labels such as `Intervallo di importo`, `Importo minimo`, and `Personalizzato` remained visible.
- 2026-09-04: Signed income and expense values keep their sign attached to the currency amount.
  The Home and Activity summary cards display `+€2,500.00` on one line at the standard font scale.
- 2026-09-04: `AppBackground` extends behind the status bar in both appearances; content is inset
  below the system icons and their light/dark contrast remains readable.
- 2026-09-04: Home exposes a labeled Add action that opens the existing transaction form. Dismissing
  that dashboard-initiated form returns to Home, rather than leaving the user in Activity.
- 2026-09-04: The emulator accessibility hierarchy exposes localized labels for Filter, Add,
  Edit, and Delete, and exposes the no-results recovery and destructive dialog actions. Manual
  TalkBack speech and traversal still require a device-assisted check; automated hierarchy
  inspection alone is not treated as a TalkBack sign-off.
- 2026-09-06: Category Settings now mirrors the iOS capability set: Settings opens a dedicated
  Android subpage with separate Expense and Income sections, and users can create, edit, and
  confirm deletion of categories. The editor keeps the category type fixed after creation,
  validates names before save, and provides native color and icon pickers. Existing transactions
  retain their saved category label after a category is deleted. The debug build and unit tests
  pass. A Pixel 7 emulator check in dark appearance covered Settings navigation, populated
  categories, native icon differentiation, the disabled fresh editor, and scrolling to every
  picker and action. Italian and large-text checks for this new screen remain open.
- 2026-09-06: Activity's Add Transaction sheet now exposes the iOS recurrence v1 contract with
  a native Repeat toggle, Weekly/Monthly/Yearly cadence and an adjustable interval. Recurrences
  materialize silently on launch and foreground return; the existing per-occurrence and
  this-and-future deletion choices remain in place. Automated recurrence date and repository
  integrity tests pass. Pixel 7 dark-appearance QA covered the scrollable editor, the expanded
  cadence controls, and the reachable Save action. Italian and large-text checks remain open.
- 2026-09-06: Add Transaction now has an Android-native receipt path: Scan receipt offers a
  camera photo or photo-picker source and states that the image is processed locally then
  discarded. The reviewable amount, date, merchant note, category suggestion, and ambiguous-total
  choices are populated only after local OCR. Pixel 7 dark-appearance QA covered the scan entry
  point, source choice, privacy copy, and the new date control. OCR needs a physical-receipt
  device check; Italian and large-text checks remain open.
- 2026-09-06: Add and Edit Transaction now open expanded and use the iOS form hierarchy: top
  Cancel/Save actions, amount, Income/Expenses, a horizontally scrollable category-card strip,
  note, date, and recurrence. The strip uses the same category-specific Android icons as Category
  Settings. Pixel 7 dark-appearance QA covered the full-height opening state, long amount entry
  with aligned EUR marker, visible category selection, and a successful Save through the top bar.
  Italian, light-appearance, large-text, and manual TalkBack checks remain open.

Track the remaining manual TalkBack check in Android issue #92; keep issue #93 open until that
check is complete.
