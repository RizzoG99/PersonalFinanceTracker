# Performance Audit Plan

## Operating model

The audit uses two passes. Screening identifies concrete candidate costs and may return no findings. Focused validation then challenges only high-impact candidates by checking reachability, frequency, input sizes, existing guards/caches, and optimization trade-offs. Audit and implementation remain separate.

Detailed evidence belongs in the workstream reports. Agent summaries are bounded and the orchestrator reads source only to resolve conflicts or validate material findings. Every accepted finding uses a stable `PERF-XXX` ID and the required severity, confidence, location, trigger, impact, evidence, recommendation, trade-offs, validation, and effort fields.

## Workstreams

### WS-UI — Rendering and state flow

- Scope: `Features/TransactionListView`, `Features/Dashboard`, `Features/Insights`, `Features/iPad`, shared SwiftUI components, and their view models/signals.
- Questions: large-list construction and identity, body-time transformations, Charts data churn, observation granularity, redundant refreshes, view-model task cancellation, and unrelated invalidations.
- Reports: `findings/rendering.md`, `findings/state-management.md`.
- Complexity: High.
- Order: first screening batch.

### WS-DATA — Persistence, I/O, caching, and algorithms

- Scope: `Models/TransactionActor.swift`, repository contracts and snapshots, import/export and backup/restore utilities, recurrence/forecast/budget/chart services, widget snapshot updates, and feature-discovery networking.
- Questions: full-store fetch frequency, repeated serialization or traversal, predicate/sort pushdown, per-mutation snapshot rebuilds, synchronous disk work, duplicate work, cache bounds/invalidation, and realistic algorithmic complexity.
- Reports: `findings/network-storage.md`, `findings/algorithms.md`.
- Complexity: High.
- Order: first screening batch.

### WS-RUNTIME — Memory, resources, concurrency, and platform costs

- Scope: receipt camera and image pipeline, Vision/Core Image recognition, task lifecycles, AVFoundation resources, timers/notifications, actors, detached tasks, and cancellation boundaries.
- Questions: retained image buffers, session teardown, frame-processing backpressure, main-actor work, actor/queue hops, unstructured-task duplication, cancellation, Sendable boundaries, and resource cleanup.
- Reports: `findings/memory.md`, `findings/concurrency.md`, `findings/platform-specific.md`.
- Complexity: High.
- Order: first screening batch.

### WS-STARTUP — Launch and initialization

- Scope: app initializer, `AppContainer`, authentication wrapper, shell composition, TipKit, notification setup, default data seeding, widget-deep-link state, and first-screen loads.
- Questions: synchronous cold-launch work, eager construction, redundant first-load refreshes, warm-launch/foreground behavior, and deferrable initialization.
- Report: `findings/startup.md`.
- Dependencies: data and runtime screening, because storage and lifecycle evidence affects launch interpretation.
- Complexity: Medium.
- Order: second batch.

### WS-VALIDATE — Cross-agent challenge

- Scope: every P0/P1 candidate and any disputed Medium finding.
- Questions: Is the path reachable and frequent? What are realistic data sizes? Does an existing guard mitigate it? Is the proposed change smaller and safer than the cost? Which metric and tool could falsify the hypothesis?
- Report: `validation-plan.md` plus confidence changes in source reports.
- Complexity: Medium to High.
- Order: after screening and startup review.

## Performance scenarios and provisional budgets

Numeric budgets are intentionally not invented before baselines. Validation will establish device-specific baselines for:

1. Cold launch with a populated multi-year store, separated from warm launch and unlock-to-shell time.
2. Activity load, search, filter changes, and sustained scrolling with thousands of transactions.
3. Repeated Dashboard/Insights navigation and period/category switching with multi-year data.
4. Add/edit/bulk-update latency including persistence and widget-snapshot refresh.
5. CSV/XLSX import preview and commit for large realistic files.
6. Receipt capture through recognized form population, including peak memory and camera energy.
7. Repeated navigation and lock/unlock cycles, checking stable memory and task/resource teardown.
8. Background/foreground recurrence and Safe-to-Spend refresh behavior.

Qualitative gates are: no avoidable main-thread stalls, scrolling targets the device refresh rate, memory returns to a stable band after repeated navigation, I/O is not duplicated, cancellation prevents stale work, and optimizations preserve correctness and maintainability.

## Prioritization and evidence rules

- P0: severe, user-visible, high-confidence issue requiring immediate measurement or remediation planning.
- P1: high-impact candidate with strong evidence or measurement.
- P2: meaningful improvement whose impact or frequency still needs validation.
- P3: low-impact, narrowly triggered, or speculative candidate.

`Confirmed` requires measurement or reproduction. Static reachability plus a concrete expensive pattern is `Strong Evidence`. Plausible smells without runtime proof are `Potential`. Code-quality concerns without a credible performance effect are not performance findings.

## Execution checkpoints

1. Reconnaissance and exclusions — completed.
2. Three independent static-screening workstreams — completed.
3. Startup review informed by screening — completed.
4. Deduplication and challenge of high-impact candidates — completed.
5. Consolidated summary, roadmap, and measurement plan — completed.
6. Focused delta review through PR #217 (`dcbb22d`) — completed.

The manifest is updated after each checkpoint. Completed reports are not repeated unless their dependencies or the audited code materially change.
