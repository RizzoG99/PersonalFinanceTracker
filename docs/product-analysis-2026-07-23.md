# Product & Market Analysis — Personal Finance Tracker (iOS)

*Date: 2026-07-23 (updated 2026-07-29: "Now" tier shipped, see note below)*

> **Update 2026-07-29:** All five "Now" tier items below have shipped: App Intent quick-add (Siri/Shortcuts, with category/type prompting and negative-amount forgiveness), daily logging reminder, persisted import mappings per file signature, Dashboard anomaly callout, `CreditScoreCard` deleted (not wired — was dead UI), and the README updated. The rest of this document (Next/Later tiers, gap analysis, competitive advantages) is unchanged and still reflects the current state.

## Executive Summary

**What it is:** A privacy-first, manual-entry personal finance tracker for iOS 26+, built with SwiftUI + SwiftData, MVVM, all data local to the device. Five tabs: Dashboard, Activity, Insights ("Compass"), Credit, Profile. EUR-only, single implicit account, expenses stored as negative Decimals.

**Target user:** A single, privacy-conscious individual (currently, essentially the developer) who manually logs or bulk-imports transactions from bank exports (CSV/XLSX), and wants analysis on top — not bank-linking automation.

**Maturity: solid mid-stage.** The analytics layer is unusually deep for an indie tracker (health score with historical snapshots, spending forecast with caching, anomaly detection, habit insights, goal pockets with a real `transfer` transaction type, pay-cycle-aware periods everywhere). Architecture is clean: repository protocol + snapshot value types + `TransactionActor` for concurrency, no import cycles, 200+ Swift Testing tests, a design-token system. What's *thin* is the platform layer: **empty entitlements, zero widgets, no sync, no watch app**. As of 2026-07-29, the App Intent quick-add and daily logging notification have closed the biggest logging-speed gaps; the app is still largely a well-built island otherwise.

**The strategic read:** Market research shows the post-Mint audience explicitly prioritizes (1) speed of logging, (2) privacy/no bank linking, (3) not being hostage to a subscription cloud service ([Vento's Reddit analysis](https://vento.money/blog/best-budget-expense-tracker-what-reddit-actually-says/), [Finny](https://getfinny.app/blog/best-budget-apps-reddit-recommends-2026)). This app is *architecturally aligned* with all three, and the Siri/Shortcuts quick-add now gives it a real out-of-app logging path — but it still lacks the two features every manual-entry competitor ships: **budgets** and **recurring transactions**.

---

## Current Feature Inventory

| Area | Shipped |
|---|---|
| Dashboard | Balance card, pay-cycle income/expense summary, greeting header, recent transactions |
| Activity | Grouped transaction history, live text search, type/date/amount filter chips, swipe-to-delete with undo banner |
| Insights ("Compass") | Health score v2 (arc gauge, component breakdown, historical snapshots, tips), spending forecast (sliding window + `DailyForecastCache`), goal pockets (with `transfer` type + `goalId`), habit observations, category trends, hero insight card, timeline anomaly detection, category pie/breakdown charts with EUR legend |
| Credit | Credit card management, utilization card, credit score card |
| Transactions | Add/edit sheet with category, amount (custom currency field), date, notes |
| Categories | Custom categories with icon grid + color token pickers, per-type (income/expense) |
| Import/Export | CSV and XLSX import with column-mapping and category-mapping wizard; CSV/XLSX export |
| Security | PIN (CryptoKit-hashed) + Face ID/Touch ID lock, PIN-confirmed "Delete All Data" wipe |
| Settings | Pay-cycle start day (drives all period math), personal info, currency display section |

## Hidden / Unfinished Features (found in code, not surfaced or incomplete)

1. ~~README "Work in Progress" is stale~~ — **done 2026-07-29**, README now reflects search/biometrics as shipped. iCloud sync and budgeting remain genuinely unbuilt.
2. **Multi-currency scaffolding exists but is dormant** — `CurrencyService` and `ProfileCurrencySection` exist, yet EUR is hardcoded throughout. Half the plumbing for currency selection is already there.
3. ~~`CreditScoreCard` renders a score with no real data source~~ — **deleted 2026-07-29** along with its manual score state; was dead UI with no data source.
4. **`TransactionType.transfer`** was added for goal pockets but isn't exposed as a general user-facing concept (e.g., transfers between future "accounts").
5. **Empty entitlements file** — no App Groups, Keychain sharing, or CloudKit container. Every platform-extension feature (widget, watch, sync) needs this bootstrapped first.

---

## Missing Features (Gap Analysis vs. Market)

Competitors examined: [MoneyCoach](https://moneycoach.ai/features) (closest analog: manual-first, privacy-first, EU-friendly), [Cashew](https://apps.apple.com/us/app/cashew-expense-budget-tracker/id6463662930) (free manual tracker), [Copilot](https://www.copilot.money/), [YNAB / Monarch](https://walletgrower.com/compare/ynab-vs-monarch-vs-copilot) (subscription bank-linkers — indirect competitors, since this app deliberately doesn't bank-link).

| Feature | User value | Why competitors have it | Complexity | Priority |
|---|---|---|---|---|
| **Budgets / spending limits per category** | The #1 reason people open a finance app; turns passive tracking into behavior change | Table stakes — every single competitor (MoneyCoach, Cashew, YNAB, Copilot) has it | **Medium** — category infra, pay-cycle periods, and `SpendingInsightService` already provide 80% of the math | **P0** (already in the README) |
| **Recurring transactions / subscription tracking** | Rent, salary, subscriptions are most of a ledger; manual re-entry is the top abandonment driver | Cashew ships it with reminders; MoneyCoach ships it; users on Reddit cite logging friction as reason #1 for quitting | **Medium** — a `RecurrenceRule` on `TransactionModel` + materialization on app launch (no background task needed) | **P0** |
| **Home-screen widget (balance / safe-to-spend)** | Glanceability = retention; interactive widgets drive [12–18% re-entry lift](https://www.forasoft.com/blog/article/9-tips-to-make-ios-app-cooler-86) | MoneyCoach ships budget widgets; Cashews ships a "Can I afford it?" widget | **Medium** — WidgetKit + App Group to share the SwiftData store | **P0** |
| **Quick add via App Intents / Shortcuts / Siri** | "Speed of logging" is the market's most-cited want | MoneyCoach ships Quick Entry + Shortcuts; [App Intents feeds Siri, Spotlight, widgets, Apple Intelligence](https://blakecrosley.com/blog/app-intents-2-ios-26-additions) — one intent, many surfaces | **Low–Medium** | **P0** |
| **iCloud sync (SwiftData + CloudKit)** | Device loss = total data loss today; the Mint shutdown made data durability a top-3 question in recommendation threads | All competitors sync; for a local-first app, *private* CloudKit sync preserves the privacy story | **Medium** — SwiftData has native CloudKit support; the migration policy (no App Store, reinstall OK) removes the usual schema-migration pain | **P1** |
| **Multi-currency** | EUR hardcoding blocks any second user and travel use | Standard everywhere | **Medium** — `CurrencyService` exists; the work is display-layer sweep, not architecture | **P1** |
| **Multiple accounts** (checking/cash/savings) | Real people have >1 pot of money; credit cards already prove the pattern | Universal | **Medium–High** — `CreditCardRepository` is the template; `transfer` type already exists | **P1** |
| **Spending notifications / bill reminders** | Habit formation and "log it before you forget" | MoneyCoach, Cashew both remind | **Low** once recurring transactions exist | **P1** |
| **Receipt photo attachment** | Manual-entry users often want proof-of-purchase | Common in manual trackers | **Low** (SwiftData external storage blob) | **P2** |
| **Apple Watch quick-log** | Fastest possible logging surface | MoneyCoach ships it | **High** | **P2** |

---

## Quick Wins (low effort, high impact) — ALL SHIPPED 2026-07-29

1. ~~App Intents "Add Transaction" + Shortcuts~~ — **shipped**: `AddTransactionIntent` reuses the add-transaction logic, prompts for category/type, forgives negative amounts. Siri/Spotlight/Shortcuts entry now exists.
2. ~~Bill/log reminders via local notifications~~ — **shipped**: daily logging reminder, skip-if-already-logged, configurable in Profile settings.
3. ~~Remember import mappings~~ — **shipped**: column and category mappings persist per file signature (headers hash), so repeat monthly imports are one tap.
4. ~~Update README / surface finished work~~ — **shipped**: README now lists search and biometrics as done.
5. ~~Anomaly alerts surfaced on Dashboard~~ — **shipped**: dismissible Dashboard callout built on `TimelineAnomalyService`.

(`CreditScoreCard`, previously flagged as dead placeholder UI, was deleted rather than wired — no real data source existed to back it.)

## Medium Projects

1. **Budgets per category, pay-cycle-native** — the pay-cycle engine is the differentiator here: budgets that reset on *your payday*, not the 1st of the month, is something even YNAB approximates awkwardly. Reuses `PayCycleService`, `CategoryModel`, `SpendingInsightService`, filter chips UI patterns.
2. **Recurring transactions** — `RecurrenceRule` on the model, materialize-on-launch, edit-series vs. edit-instance. Unlocks reminders, subscription insights ("you spend €47/mo on subscriptions"), and better forecasts (`SpendingForecastService` gets known-future cash flows instead of pure extrapolation).
3. **Widgets: balance + safe-to-spend + budget rings** — requires the App Group/entitlements bootstrap; after that, `DashboardViewModel`'s snapshot pattern maps cleanly onto timeline entries.
4. **iCloud private sync** — flip SwiftData to a CloudKit container. Given the no-migration policy, this is a rare cheap window to do it *before* the schema calcifies further. Also the honest answer to "what if I lose my phone" for a local-only app.
5. **Multi-currency** — finish what `CurrencyService` started; store currency per transaction, display in home currency.

## Major Initiatives

1. **Accounts model** — promote the implicit single account to first-class `AccountModel` (checking, cash, savings, linking existing credit cards), with `transfer` between them. This is the schema change that unlocks net-worth tracking and makes the app a Monarch-class ledger. Do it *before* iCloud sync locks the schema, or accept a reinstall (policy allows it).
2. **Apple Watch app** — 3-tap logging (category grid → amount → done). Highest-leverage logging surface, but a whole new target.
3. **On-device AI assist (see below)** — natural-language entry and import auto-categorization via Apple's on-device Foundation Models.

## Technical Opportunities (existing code to leverage)

- **Snapshot architecture → widgets & watch for free-ish**: `TransactionSnapshot`/`HealthScoreSnapshot`/`DailyForecastCacheData` are `Sendable` value types already decoupled from SwiftData — exactly what widget timelines and watch connectivity need.
- **`ITransactionRepository` protocol** means every new surface (intent, widget, watch) can be tested against `MockTransactionRepository` — the test infra is a genuine asset here.
- **`FinancialHealthService` + snapshots** → health-score *history chart* ("your score over 6 months") is mostly a query + chart away.
- **`transfer` type + `goalId`** → generalizes to account transfers with minimal model change.
- **`CreditScoreCard` placeholder** → either wire it to something real (utilization-derived score) or delete it; today it's dead UI.
- **`DataWipeService` + PIN confirmation** → reusable pattern for "export then wipe" data-portability flow, a strong privacy-story feature.

## AI Opportunities (only where it solves a real problem)

1. **Import auto-categorization** — the *real* pain in the current workflow: after CSV/XLSX import, mapping dozens of merchant strings to categories by hand. On-device [Foundation Models](https://www.ksolves.com/blog/mobile-app-development/ios-26-features) (iOS 26, no server, fits the privacy story) can classify "CARREFOUR MARKET 1234" → Groceries. Fallback: a learned string-match dictionary (no AI at all) gets 70% of the value — ship that first.
2. **Natural-language quick add** — "coffee 3.50" → parsed transaction. Pairs with the App Intent; the on-device model does entity extraction. Skip a chatbot; this is a parser, not a conversation.
3. **Narrative insights** — narrative summaries already exist via `SpendingInsightService` with deterministic code. Keep it deterministic; AI adds cost and nondeterminism for prose already produced. *Recommend against.*

## Competitive Advantages (innovation candidates competitors don't have)

1. **Pay-cycle-native "Safe to Spend until payday"** — combine `PayCycleService` + forecast + recurring commitments into one number on Dashboard/widget/Live Activity. Cashews grades affordability A–F; nobody does it *anchored to your actual payday*. This is the flagship differentiator — the whole app already thinks in pay cycles.
2. **End-of-pay-cycle Live Activity** — last 3 days before payday, a [Live Activity](https://swiftcrafted.dev/article/live-activities-dynamic-island-ios-26-swiftui-activitykit-guide) showing remaining safe-to-spend. Novel, on-trend, and only sensible for a pay-cycle-aware app.
3. **Privacy-first positioning made explicit** — "your data never leaves your device (optionally your private iCloud)" + export-anytime + PIN-wipe. The market is *actively searching* for this post-Mint; competitors can't credibly claim it because their business model is bank aggregation.
4. **Bank-statement import intelligence** — per-bank import profiles (delimiter, date format, column mapping, merchant→category memory) that make monthly statement import a one-tap ritual. Bank-linking apps can't compete here; other manual apps do naive CSV import.
5. **Health score with receipts** — score history is already snapshotted; show *why* it moved ("score dropped 4 pts: utilization up"). Credit-score apps do this for credit; nobody does it for holistic finance health.
6. **Anomaly-driven "unusual spend" review** — a weekly digest of `TimelineAnomalyService` findings framed as a 60-second review ritual, not a feed.

---

## Prioritized Roadmap

### Now — High Impact / Low Effort — ALL SHIPPED 2026-07-29
1. ~~App Intent quick-add (+ Shortcuts/Siri/Spotlight for free)~~ ✅
2. ~~Daily logging reminder notification~~ ✅
3. ~~Persist import column/category mappings per bank file signature~~ ✅
4. ~~Surface anomalies on Dashboard; wire or delete `CreditScoreCard`; update README~~ ✅ (deleted `CreditScoreCard`)

### Next — High Impact / Medium Effort
5. **Budgets** (pay-cycle-native — the differentiator framing)
6. **Recurring transactions** (then bill reminders, then better forecasts)
7. Entitlements bootstrap + **balance/safe-to-spend widget**
8. **iCloud sync** — do this while the no-migration policy still holds
9. "Safe to Spend until payday" as the Dashboard hero number

### Later — Large Investments
10. Accounts model + net worth (schema change: sequence before/with sync)
11. Multi-currency completion
12. On-device AI import categorization (string-match dictionary first)
13. Apple Watch quick-log; payday Live Activity

**Sequencing note:** items 10 (accounts) and 8 (sync) interact — schema changes after CloudKit adoption get harder even with the reinstall policy, so decide the account model shape before turning on sync.

---

## Sources

- [Vento — what Reddit actually recommends](https://vento.money/blog/best-budget-expense-tracker-what-reddit-actually-says/)
- [Finny — Reddit budget app picks 2026](https://getfinny.app/blog/best-budget-apps-reddit-recommends-2026)
- [WalletGrower — YNAB vs Monarch vs Copilot](https://walletgrower.com/compare/ynab-vs-monarch-vs-copilot)
- [Techno-Pulse — AI finance tools 2026](https://www.techno-pulse.com/2026/04/best-ai-personal-finance-tools-in-2026.html)
- [MoneyCoach features](https://moneycoach.ai/features)
- [Cashew on the App Store](https://apps.apple.com/us/app/cashew-expense-budget-tracker/id6463662930)
- [Cashews — Can I afford it?](https://cashews.finance/)
- [Copilot Money](https://www.copilot.money/)
- [Forasoft — native iOS features 2026](https://www.forasoft.com/blog/article/9-tips-to-make-ios-app-cooler-86)
- [Swift Crafted — Live Activities iOS 26](https://swiftcrafted.dev/article/live-activities-dynamic-island-ios-26-swiftui-activitykit-guide)
- [Blake Crosley — App Intents 2.0](https://blakecrosley.com/blog/app-intents-2-ios-26-additions)
- [Ksolves — iOS 26 developer features](https://www.ksolves.com/blog/mobile-app-development/ios-26-features)
