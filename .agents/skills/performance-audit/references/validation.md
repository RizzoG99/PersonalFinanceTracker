# Validation and Consolidation

## Independent review

Give the reviewer only the candidate reports, audited snapshot, and the minimum architecture context. Ask for one verdict per ID:

- `Keep`: evidence, severity, and confidence are justified.
- `Downgrade`: the pattern is real but impact/confidence is overstated.
- `Reject`: reachability, cost, or claimed behavior is unsupported.
- `Merge`: evidence is useful but belongs under another root finding.

For every verdict, require validated severity, confidence, P0–P3 priority, exact rationale, relevant mitigations, and corrections to the recommendation. Reviewers may return no retained findings.

## Deduplication

Merge findings when one is the mechanism, lifecycle manifestation, or downstream symptom of another root cause. Preserve:

- every exact call-chain or complexity fact;
- phase-specific scenarios such as cold launch versus foreground;
- validation metrics that could falsify each manifestation;
- original IDs in a consolidation note.

Report both raw observation counts and consolidated root counts. Priority lists use root findings only.

## Priority

- `P0`: measured or reproducible severe problem requiring immediate investigation.
- `P1`: high-impact, high-confidence candidate ready for focused measurement and, if proven, implementation.
- `P2`: meaningful candidate whose scale, trigger, or trade-off needs focused validation.
- `P3`: low-impact or speculative item; retain the simpler code unless measurement changes the ranking.

Easy work does not outrank high-impact work solely because it is easy.

## Measurement plan

For every P0/P1, record:

1. Reproducible scenario and realistic dataset/device conditions.
2. Baseline metrics and run protocol.
3. Tools and instrumentation points.
4. Optimization hypothesis.
5. Before/after comparison method.
6. Functional and performance regression checks.
7. Expected qualitative outcome without speculative percentages.

Prefer distributions or repeated runs over one timing. Separate cold/warm launch, visible/hidden work, simulator/device, and debug/release-like configurations. Record environment details beside results.

## Consolidated completion check

- P0/P1 candidates were independently reviewed when possible.
- Unsupported claims were rejected or downgraded.
- Root causes are unique in the priority list.
- `Confirmed` findings include reproducible measurement evidence.
- Unmeasured findings say so prominently.
- Recommendations state correctness and maintenance risks.
- Areas without device, profiler, production-data, or query-plan evidence are explicit.
