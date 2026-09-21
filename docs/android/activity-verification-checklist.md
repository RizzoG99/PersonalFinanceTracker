# Android Activity Verification Checklist

Use this checklist for issue #92 after installing a debug build on an Android emulator or physical device. Record the device, Android version, appearance, and result for every row.

| Area | Verify |
| --- | --- |
| Compact layout | Phone portrait and landscape: search, filter button, rows, edit sheet, and floating add action remain reachable without clipped text. |
| Wide layout | Tablet or landscape large window: the list remains readable, the filter sheet scrolls, and no control depends on a fixed screen width. |
| Appearance | Light and dark mode: income/expense remain understandable from their explicit sign and not colour alone. |
| Large text | Largest practical system font scale: long notes, categories, large amounts, and Italian strings wrap without hiding actions. |
| TalkBack | Read order includes screen title, search, active filters, row note/category/date/amount, edit, delete, and the confirmation choices. Decorative icons are not announced. |
| Keyboard and sheets | Amount and note fields stay visible when the keyboard opens; sheet dismissal preserves no unintended partial mutation. |
| States | Confirm populated, empty, no-results, operation error, disabled Save, add/update success, normal deletion with Undo, and both recurring deletion choices. |
| Content stress | Use long Italian text, large positive/negative amounts, and enough transactions to scroll past the first viewport. |

No device or emulator was attached when this checklist was created. The build and unit suite are not substitutes for these runtime checks.
