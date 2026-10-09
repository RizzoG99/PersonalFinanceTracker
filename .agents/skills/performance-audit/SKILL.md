---
name: performance-audit
description: Runs or resumes an evidence-driven, project-wide performance audit with bounded subagents, persistent reports, independent validation, and a measurement roadmap. Use for repository-wide performance audits or an existing `.performance-audit/`. Do not use for a single known regression or for implementing existing findings.
---

# Performance Audit

Audit performance without changing production code. Follow the repository's `AGENTS.md`, preserve unrelated worktree changes, and adapt the investigation to the discovered architecture.

## Route

- **Start or resume an audit:** read [`references/workflow.md`](references/workflow.md) and [`references/finding-schema.md`](references/finding-schema.md).
- **Challenge, consolidate, or prioritize findings:** read [`references/validation.md`](references/validation.md) and [`references/finding-schema.md`](references/finding-schema.md).
- **Implement findings:** finish or read the audit, then return control to the user. Treat implementation as a separate task with its own authorization, baseline, tests, and before/after measurement.

For SwiftUI workstreams in this repository, use `$swiftui-pro` and load only its performance, data-flow, and concurrency references that the scope needs. Use `$graphify` as the first architecture index when its local graph exists, then validate important claims against source.

## Invariants

- `.performance-audit/manifest.json` is the resumable source of truth. Preserve completed reports and stable finding IDs.
- A code pattern is not a measured bottleneck. Classify evidence as `Confirmed`, `Strong Evidence`, or `Potential` using the finding schema.
- Detailed evidence stays in reports; orchestration context carries scopes, decisions, counts, top findings, and limitations.
- An investigation may return no findings. Never manufacture optimization work.
- Delegate only materially independent scopes, normally in batches of two to four when subagents are available. Give each agent a disjoint scope, ID range, report path, and bounded final response.
- Independently challenge P0/P1 candidates when useful. Deduplicate by root cause before counting or prioritizing.
- Record the audited commit and dirty-worktree state. Never overwrite, revert, stage, or expose unrelated user work.
- Final recommendations remain measurement-gated. Report every profiler, device, dataset, or coverage limitation explicitly.
