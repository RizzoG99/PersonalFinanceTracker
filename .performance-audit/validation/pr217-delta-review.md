# PR #217 Performance Audit Delta Review

## Scope

The original static audit was completed against `b91ee335d57e535fa736f011bf348188607d178c`. Before publication, `dcbb22ded9a08fb4272c352635ce5796d7d5e825` (PR #217) changed Dashboard, Insights, iPad presentation, and the old forecast/cache path. This focused review checks only the findings whose evidence intersects that diff. It adds no runtime measurements and changes no production code.

## Dispositions

### PERF-203 — Resolved

PR #217 removes `SpendingForecastService`, `DailyForecastCache`, the repository cache APIs, and `CompassViewModel.computeForecast()`. The unchanged-cache rewrite described by PERF-203 is no longer reachable. Retain the ID as historical audit evidence, but exclude it from the active roadmap and current root count.

### PERF-204 — Supporting evidence retired

The repeated-filter forecast implementation was removed with the old Insights forecast. The replacement `CycleSummaryService.compute` builds current-cycle, historical, category, and chart accumulators in one transaction loop (`CycleSummaryService.swift:77-98`). PERF-204 was already consolidated beneath PERF-112 rather than counted as a root finding; its removal reduces supporting evidence but does not resolve PERF-112.

### PERF-110 / PERF-200 — Keep

The global revision paths still fan out to Dashboard, Activity, Insights, habit snapshot, Safe-to-Spend snapshot, and committed-spending work on iPhone (`MainTabView.swift:274-300`). The iPad revision and startup paths still reload multiple models and both snapshots (`IPadRootView.swift:102-118`). PR #217 changes work performed inside some consumers but does not introduce shared snapshots, scoped invalidation, or coalescing.

### PERF-111 — Keep

Insights still calls `load()` from both `payCycleAware` and `onAppear`, and after the add sheet closes (`InsightsView.swift:47-50`). `CompassViewModel.load()` still launches an unowned task without coalescing or generation checks (`InsightsViewModel.swift:76-85`). The duplicate/overlapping-loader finding remains supported.

### PERF-112 — Keep, evidence updated

The removed hero and forecast computations reduce Insights work. The retained model still filters the full snapshot and computes health, explorer, habits, and averages on the main actor (`InsightsViewModel.swift:85-104`). Dashboard now computes Safe to Spend, cycle summary, habits/check-in state, anomaly data, budgets, and reminders after only the top-five recent pass is detached (`DashboardViewModel.swift:92-124`). The exact workload changed, but the root main-actor multi-pass concern remains Strong Evidence and P1 pending measurement.

### Startup scenarios — Keep

PR #217 adds iPad inspector state and Dashboard detail content but does not change the startup/revision refresh ownership described by the audit. PERF-401/PERF-402 remain validation scenarios under PERF-110.

## Current disposition after the delta

- Historical snapshot: 21 raw observations, 16 consolidated root findings.
- Removed by PR #217: PERF-203 root finding and PERF-204 supporting observation.
- Current active roots: 15 — 6 P1, 7 P2, 2 P3.
- Current confidence: 12 Strong Evidence, 3 Potential, 0 Confirmed.
- All retained recommendations remain measurement-gated.

## Limitations

This was a targeted static diff review. It did not repeat unaffected workstreams, profile a device, measure the richer month-card UI, or establish performance improvement from PR #217. Source line references describe `dcbb22d` and may drift after later commits.
