# Android accessibility

- Use `stringResource` for every visible label and content description. Decorative icons use a
  null content description; meaningful icons have a concise localized description.
- Structure headings with `semantics { heading() }`, expose state changes with an appropriate live
  region, and keep TalkBack order aligned with visual reading order.
- Preserve at least 48 dp touch targets. Do not replace buttons with raw pointer or tap handlers.
- Test with large system font scale: text must reflow, controls must remain reachable, and essential
  values or actions must not be clipped.
- Do not rely on color for income/expense, selection, validation, charts, or status. Pair it with
  sign, text, icon, position, or accessible summary.
- Verify contrast in light and dark themes. Treat dialogs, bottom sheets, snackbars, and transient
  feedback as part of the TalkBack flow, not decorative overlays.
- For charts or custom visualizations, provide a textual summary with the key values and trend.
