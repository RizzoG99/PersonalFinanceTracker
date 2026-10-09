# Performance Audit Workflow

## Mode selection

Inspect `.performance-audit/manifest.json` first when it exists.

- `IN_PROGRESS`: resume incomplete workstreams without repeating completed reports.
- `COMPLETED` at the current code snapshot: summarize the result and ask whether the user wants measurement, implementation, or a new audit.
- `COMPLETED` after material code changes: identify affected workstreams from the diff and reopen only those scopes, preserving IDs and prior evidence.
- No manifest: begin reconnaissance.

## Phase 1 — Reconnaissance

Map the repository before detailed review:

1. Record the commit, branch, dirty state, languages, frameworks, targets, entry points, dependencies, persistence/network layers, background work, tests, benchmarks, and profiling tools.
2. Identify performance-sensitive user journeys and realistic data-size dimensions.
3. Exclude generated code, build output, vendored source, local graph output, static assets, and historical documents unless directly implicated.
4. Use repository indexes and targeted symbol searches before broad file reads.
5. Create or update:

```text
.performance-audit/
├── manifest.json
├── architecture.md
└── audit-plan.md
```

Reconnaissance is complete when the plan has non-overlapping workstreams, relevant modules, dependencies, complexity, execution order, exclusions, and evidence limitations. Detailed screening begins only after this checkpoint.

## Phase 2 — Screening

Choose workstreams from the architecture rather than copying a fixed list. Common scopes include rendering/state, persistence/I/O, algorithms, memory/resources, concurrency, startup, and platform-specific work.

When subagents are available and worthwhile:

- Run two to four independent scopes at a time.
- Give each scope an exclusive finding-ID range and report paths.
- Limit source inspection to the named modules plus direct call sites needed for reachability.
- Require exact paths/lines, trigger frequency, realistic scale, existing guards/caches, trade-offs, and evidence limitations.
- Keep each final response near 400 words: scope, counts, top three, limitations, and report paths.
- Let agents write only their assigned reports; the orchestrator owns the manifest and consolidated deliverables.

The orchestrator updates the manifest when a workstream starts and completes. Do not accept a finding merely because it matches a performance smell; require the structure in `finding-schema.md`.

## Phase 3 — Focused investigation

For promising candidates, trace:

1. Reachability from a real user/lifecycle event.
2. Execution frequency and overlap with other work.
3. Realistic input size and worst-case scaling.
4. Existing coalescing, caching, cancellation, bounds, and framework optimizations.
5. Correctness and maintainability costs of the proposed change.

Prefer falsifiable validation scenarios over speculative fixes. Memoization, caching, parallelism, and background execution each require an invalidation, ordering, cancellation, and resource-cost analysis.

## Phase 4 — Independent review

Use `validation.md`. Challenge every P0/P1 candidate and disputed Medium finding. The reviewer should not be the discovering agent when an independent agent is available.

The orchestrator then:

- keeps, downgrades, or rejects each candidate;
- merges symptoms that share one root cause while retaining their evidence and scenarios;
- separates raw observation counts from consolidated root-finding counts;
- ranks P0–P3 by user impact, frequency, confidence, scope, effort, and regression risk.

## Phase 5 — Deliverables

Create only relevant workstream reports, plus:

```text
.performance-audit/
├── findings/
├── validation/
├── summary.md
├── optimization-roadmap.md
└── validation-plan.md
```

The summary includes:

1. Executive summary and repository coverage.
2. Raw and consolidated counts by severity and confidence.
3. Findings grouped by priority.
4. Top ten recommendations.
5. Architectural concerns and quick wins.
6. Profiling recommendations and unverified hypotheses.
7. Areas not analyzed and report paths.

The roadmap keeps audit and implementation separate. The validation plan gives every P0/P1 a reproducible scenario, baseline metrics, tools, optimization hypothesis, validation method, regression checks, and qualitative outcome.

## Manifest

Track at least:

- audit version and status;
- repository path, commit, branch, and dirty state;
- creation/update timestamps;
- each workstream's ID, scope, status, assigned agent, reports, finding count, dependencies, and completion time;
- raw and consolidated result counts after review.

Allowed workstream statuses are `PENDING`, `IN_PROGRESS`, `COMPLETED`, and `BLOCKED`. A completed audit uses `COMPLETED`; incomplete work remains explicit rather than silently disappearing.

## Completion criterion

The audit is complete when every planned workstream has a terminal status, every retained finding is evidence-classified and independently challenged where required, overlaps are consolidated, the manifest is valid, all report paths exist, and the final response states that static evidence is not measurement.
