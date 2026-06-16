# Feature: Hero Insight Card Redesign

## Problem
The Hero Insight card renders as a fully saturated solid-color fill (bright green/red) that breaks the dark glass-morphism aesthetic of the rest of the Compass page. Text contrast is also poor because white-on-saturated-color reads noisily. Every other card on the page (Health Score, chart, etc.) uses a dark glass background.

## Approach
Replace the tinted `GlassCard(tint: tintColor)` with a standard untinted `GlassCard` matching the Health Score card's visual weight. The trend direction is communicated through two accent elements only: a colored SF Symbol icon and a small colored pill/badge (e.g., "▲ 23%" or "▼ 91%"). Title uses `.textPrimary`, subtitle uses `.textMid`. No card-wide color fill.

## Key decisions
- Remove `GlassCard(tint:)` entirely for this card — pass no tint, let it render dark like other cards
- The `emoji` field on `HeroInsight` is currently unused; can now be surfaced as a small label inside the pill or next to the title instead of the large SF Symbol
- Icon color stays as `tintColor` (.positive / .negative / .accentIndigo) — this alone is sufficient to signal direction
- A small pill badge (colored background at ~15% opacity, colored text) showing the percentage change adds the numerical context currently missing ("91% less" is buried in the title string — extracting it to a badge makes it scannable)
- Text in the title should be simplified now that the pill carries the number (e.g., "Under last month's pace" instead of "Spending 91% less")
- No changes to `HeroInsight` model or `SpendingInsightService` — purely a view change

## Architecture notes

**Files to modify:**
- `Features/Insights/Components/HeroInsightCard.swift` — remove `GlassCard(tint:)`, restructure layout: icon (colored) + VStack(title, subtitle) + Spacer + pill badge

**Files to create:** None

**SwiftData schema changes:** None

## Where to start
Rewrite `HeroInsightCard.body` — swap `GlassCard(tint: tintColor)` for `GlassCard()`, then add the pill badge as a trailing element in the HStack using `tintColor.opacity(0.15)` background and `tintColor` foreground text.
