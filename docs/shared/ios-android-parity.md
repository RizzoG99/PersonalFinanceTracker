# iOS and Android Parity Matrix

Index of every Android capability, keyed by stable parity ID. The GitHub issue is the contract and evidence record (#75); this table only points to it. Refreshed for #282 on 2026-11-18.

## Baselines

| Baseline | iOS commit | Android comparison | Applies to |
| --- | --- | --- | --- |
| Historical | `83bc9db` (1.0 (1)) | `babc1e9` onwards | M1 and M2 capabilities filed before October 2026. Their verdicts stay valid only for this baseline. |
| Drift 2026-10 | `b649dff` | `a498bc9` (branch `codex/android-native`, draft PR #146) | `DRIFT-2026-10-*` capabilities inventoried in #281. Includes iOS Unreleased changes at that commit. |

Android columns copy the **Android Native** project (Status / Evidence) as of 2026-11-18. When they disagree with this file, the project wins; update this file in the same PR that moves a capability to Verified.

## Product-scope decisions

| ID | Decision | Approved by |
| --- | --- | --- |
| D-01 | Credit cards are unused iOS remnants and are **not** Android product scope: no credit-card screen, flow or parity row. The `credit_cards` Room table and `CreditCardRepository` stay as legacy persistence and must not be dropped just to change scope. | Owner, 2026-10-31 (#75, #281) |
| D-02 | Direct iOS-to-Android onboarding migration is deferred to #84–#87 and is not Android v1. | Owner (#75) |
| D-03 | Future iOS product ideas (`FUTURE-*`) are Deferred backlog, not parity blockers, until explicitly scheduled. | Owner, 2026-10-31 (#281) |

## Historical capabilities (`83bc9db`)

| Parity ID | Capability | Issue | Status / Evidence |
| --- | --- | --- | --- |
| M0-PROGRAM | Parity program, gate and capability template | #75 | In Progress / Contract ready |
| M1-FOUNDATION | Foundation tracker | #76 | In Progress / Unassessed |
| M1-DATA | Data and persistence parity | #83 | Done / Unassessed |
| M1-APP-BOOT | Application bootstrap and cold launch | #109 | Done / Contract ready |
| M1-NAV-SHELL | Primary navigation shell | #110 | Done / Contract ready |
| M1-UI-STATES | Loading, empty, error and retry states | #111 | Done / Contract ready |
| M1-L10N-BASE | English and Italian foundation localization | #112 | Done / Contract ready |
| M1-A11Y-BASE | Foundation accessibility (human TalkBack pass open) | #113 | In Progress / Verifying |
| M1-CI-GATE | Android CI gates | #114 | Done / Verified, Matched |
| M1-DEVICE-SMOKE | Physical-device smoke bundle | #115 | Todo / Contract ready |
| M1-DATA-CORE | Core finance persistence and repositories | #116 | Done / Contract ready |
| M1-DATA-ADV | Advanced finance persistence and repositories | #117 | Done / Gap found |
| M1-DATA-PREFS | Profile and preference persistence | #118 | Done / Gap found |
| M1-DATA-MIGRATIONS | Room schema migrations and durability | #119 | Done / Gap found |
| M2-CORE | Core finance tracker | #77 | In Progress / Unassessed |
| M2-DASHBOARD | Pay cycle, categories and dashboard metrics | #88 | Todo / Unassessed |
| M2-ACT-CRUD | Activity CRUD and filters | #89 | In Progress / Unassessed |
| M2-ACT-FILTERS | Activity advanced filters (pilot) | #90 | In Progress / Gap found |
| M2-ACT-RECUR-DELETE | Recurrence-safe Activity deletion | #91 | Todo / Unassessed |
| M2-ACT-A11Y | Activity accessibility and device layouts | #92 | Todo / Unassessed |
| M2-VISUAL | iOS-aligned visual system and app shell | #93 | In Progress / Unassessed |
| M2-CATEGORY-SETTINGS | Category settings | #95 | Todo / Unassessed |
| M2-RECURRING | Recurring transaction workflows | #96 | Todo / Unassessed |
| M3-ADVANCED | Advanced finance tracker | #78 | Todo / Unassessed |
| M3-RECEIPT | Receipt scanning and review | #97 | Todo / Unassessed |
| M4-IMPORT-EXPORT | CSV/XLSX import and export tracker | #79 | Todo / Unassessed |
| M5-SECURITY | Security and backup tracker | #80 | Todo / Unassessed |
| M6-RELEASE | Release gate | #81 | Todo / Unassessed |
| M7-MAINTENANCE | Post-launch maintenance | #82 | Todo / Unassessed |
| M4-MIGRATION | iOS-to-Android migration (#84 archive, #85 encryption, #86 fixtures) | #87 | Deferred (D-02) |

Closed gap and CI issues #105, #106, #107, #108, #120–#147 and #368 keep their evidence on the issue; they belong to the capability named in their title.

## Current iOS drift (`b649dff`)

| Parity ID | Capability | Issue | Status / Evidence |
| --- | --- | --- | --- |
| DRIFT-2026-10-ALIGNMENT | October 2026 drift tracker | #281 | Todo / Contract ready |
| DRIFT-2026-10-CONTRACTS | This matrix and the shared data contract | #282 | In Progress / Contract ready |
| DRIFT-2026-10-PLAN | Plan tab; phone and tablet navigation | #283 | Todo / Gap found |
| DRIFT-2026-10-TRAVELS | Travels grouping, management and assignment | #284 | Todo / Gap found |
| DRIFT-2026-10-BULK | Activity multi-select, bulk category edit, Undo | #285 | Todo / Gap found |
| DRIFT-2026-10-PAGING | Activity paging and coalesced refreshes | #286 | Todo / Gap found |
| DRIFT-2026-10-UNDO | No-op Undo after saving from + removed | #287 | Done / Verified |
| DRIFT-2026-10-FORM | Transaction drafts, focus, keyboard and sheet continuity | #288 | Todo / Gap found |
| DRIFT-2026-10-CALCULATOR | Amount calculator and field navigation | #289 | Todo / Gap found |
| DRIFT-2026-10-INLINE-CATEGORY | Inline category creation (form and import) | #290 | Todo / Gap found |
| DRIFT-2026-10-CATEGORY-DISPLAY | Localized category names and search; custom styles | #291 | Todo / Gap found |
| DRIFT-2026-10-CATEGORY-REPAIR | Category rename propagation and link repair | #292 | Todo / Gap found |
| DRIFT-2026-10-CATALOG | Category icon/colour catalogue and default refresh | #293 | Todo / Gap found |
| DRIFT-2026-10-RECURRING-MANAGER | Recurring rules managed apart from their transactions | #294 | Todo / Gap found |
| DRIFT-2026-10-FIXED-DETECT | Fixed-expense detection; forecast-only rules | #295 | Todo / Gap found |
| DRIFT-2026-10-FIXED-REVIEW | Fixed-expense review cards and missed payments | #296 | Todo / Gap found |
| DRIFT-2026-10-CALENDAR | Financial calendar and Home upcoming preview | #297 | Todo / Gap found |
| DRIFT-2026-10-SAFE | Safe to Spend, buffer, "using buffer" warning and what-if (D-06) | #298 | In Progress / Verifying |
| DRIFT-2026-10-CYCLE | Home "This cycle" card and spending pace | #299 | Todo / Gap found |
| DRIFT-2026-10-GOAL-TRANSFERS | Transfer type and recurring goal contributions (review copy moved to #296, D-01) | #300 | Done / Verified |
| DRIFT-2026-10-PROJECTIONS | Goal ETA and required monthly savings | #301 | Todo / Gap found |
| DRIFT-2026-10-RECAP | Monthly recap and payday notification | #302 | Todo / Gap found |
| DRIFT-2026-10-BREAKDOWN | Insights Breakdown explorer | #303 | Todo / Gap found |
| DRIFT-2026-10-HEALTH | Health Score formulas and preferences | #304 | Todo / Gap found |
| DRIFT-2026-10-PATTERNS | Insights patterns and Home anomalies | #305 | Todo / Gap found |
| DRIFT-2026-10-BUDGETS | Income/expense budgets and cycle progress | #306 | Todo / Gap found |
| DRIFT-2026-10-PULSE | Financial Pulse check-in and quick logs | #307 | Todo / Gap found |
| DRIFT-2026-10-PROFILE | Profile settings and first-run onboarding | #308 | Todo / Gap found |
| DRIFT-2026-10-DISCOVERY | Feature discovery and What's New | #309 | Todo / Gap found |
| DRIFT-2026-10-RECEIPT-OCR | Layout-aware receipt parsing | #310 | Todo / Gap found |
| DRIFT-2026-10-RECEIPT-CAMERA | Receipt camera | #311 | Todo / Gap found |
| DRIFT-2026-10-RECEIPT-CATEGORY | Receipt category inference and learned mappings | #312 | Todo / Gap found |
| DRIFT-2026-10-IMPORT-PROFILES | Saved import profiles and mapping drafts | #313 | Todo / Gap found |
| DRIFT-2026-10-IMPORT-INTEGRITY | Atomic import and recurring reconciliation | #314 | Todo / Gap found |
| DRIFT-2026-10-EXPORT | CSV/Excel sharing and round trip | #315 | Todo / Gap found |
| DRIFT-2026-10-RESTORE-ATOMIC | Backup validation and atomic restore | #316 | Todo / Gap found |
| DRIFT-2026-10-BACKUP-LINKS | Backup identities, category links, rules, goal contributions (backup v2 = whole Android snapshot, approved deviation D-01) | #317 | In Progress / Verifying |
| DRIFT-2026-10-DRIVE | Encrypted Google Drive backup | #318 | Todo / Gap found |
| DRIFT-2026-10-PRIVACY | Foreground relock and app-switcher privacy (implemented in `dd9c4f4`) | #319 | In Progress / Verifying |
| DRIFT-2026-10-DESTRUCTIVE | Authenticated PIN change and data reset | #320 | Todo / Gap found |
| DRIFT-2026-10-WIDGETS | Home-screen widgets | #321 | Todo / Gap found |
| DRIFT-2026-10-SHORTCUTS | App shortcuts and deep links | #322 | Todo / Gap found |
| DRIFT-2026-10-SDK | SDK/toolchain for Google Play | #323 | Todo / Gap found |
| DRIFT-2026-10-PLAY-RELEASE | Signed AAB, listing and closed test | #324 | Todo / Gap found |
| DRIFT-2026-10-REGRESSION | Cross-platform scenario fixtures and evidence matrix | #325 | Todo / Gap found |
| DRIFT-2026-10-TEST-APP | Isolated test app and large-ledger fixtures | #326 | Todo / Gap found |

## Open gaps and defects outside #281

| Issue | Parent capability | Status / Evidence |
| --- | --- | --- |
| #376 Delete Undo never expires (fixed by #394) | M2-ACT-CRUD | In Progress / Verifying |
| #377 + button covers Insights snackbars | M2-VISUAL | Todo / Gap found |
| #382 TalkBack users cannot delete on phones | M2-ACT-A11Y | Todo / Gap found |
| #386 Swipe can delete the row that moved into place | M2-ACT-CRUD | Todo / Gap found |
| #390 Delete Undo not batched | M2-ACT-RECUR-DELETE | Todo / Gap found |
| #398 Crash leaving the app while the keyboard opens | DRIFT-2026-10-FORM | Todo / Gap found |
| #419 Keyboard does not return after unlock over a sheet | DRIFT-2026-10-PRIVACY | Todo / Unassessed |
| #391, #417 Intermittent instrumented tests | M1-CI-GATE | Todo / Unassessed |

## Deferred future backlog (D-03)

#327 Inbox, #328 Why spending changed, #329 Predictable expenses, #330 Opening balance, #331 Essential vs discretionary, #332 Runway, #333 Ask in natural language, #334 Affordability, #335 What-if, #336 Goal impact, #337 Spend check, #338 Restore hidden suggestions, #339 Last-payment voice query, #340 Wallet quick log. Parity IDs `FUTURE-FUTURE-*` on each issue; all Deferred / Unassessed.

## Rules

- Android v1 is complete only when every required row is `Matched` or `Matched with approved deviations` (#75).
- A behaviour change affecting financial calculations, imports, exports, archives, or backups requires an update here and in `android-v1-data-contract.md`.
- A new iOS capability gets a parity ID and an issue before it gets a row here.
- Platform implementation may differ, but the user-visible result and data safety must remain equivalent unless explicitly approved otherwise.
