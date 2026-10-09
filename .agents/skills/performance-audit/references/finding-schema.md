# Finding Schema

## Evidence classes

- `Confirmed`: impact was reproduced or measured with recorded conditions and results.
- `Strong Evidence`: a reachable, concrete expensive pattern is established, but runtime impact is unmeasured.
- `Potential`: a plausible bottleneck whose frequency, scale, or cost still needs proof.

Static complexity alone is not `Confirmed`. Never invent measurements, improvements, device results, query plans, or profiler output.

## Severity

- `Critical`: measured or reproducible severe degradation, resource exhaustion, or unusable critical flow.
- `High`: credible material impact on a common or critical flow, supported by strong reachability/frequency evidence.
- `Medium`: meaningful cost with narrower triggers, scale dependence, mitigation, or incomplete impact evidence.
- `Low`: bounded, infrequent, or likely immaterial cost; generally measurement-first.

Severity and confidence are independent. A high-severity static risk can remain `Strong Evidence`; a tiny measured inefficiency can be `Confirmed` and Low.

## Required format

```markdown
## PERF-XXX: Short descriptive title

Severity:
Critical | High | Medium | Low

Confidence:
Confirmed | Strong Evidence | Potential

Category:
Rendering | State Management | Memory | CPU | Network | Storage | Concurrency | Startup | Algorithm | Other

Location:
- File: exact/path/to/file
- Lines: start-end
- Symbol: function/class/view

Description:
What the implementation does and why it is a performance concern.

Root Cause:
The design or control/data-flow decision causing the work.

Trigger:
The real event and conditions that execute it.

Impact:
Expected user or resource effect, without fabricated numbers.

Evidence:
Reachability, repetition, complexity, allocations, call chain, or recorded measurement. Credit existing mitigation.

Recommended Optimization:
The smallest credible strategy, gated by evidence.

Trade-offs:
Correctness, freshness, memory, ordering, cancellation, complexity, and maintenance risks.

Validation:
A scenario and metrics capable of proving or rejecting the hypothesis.

Estimated Effort:
Small | Medium | Large
```

## Acceptance checks

Before accepting a finding, verify:

- The exact source and symbol exist in the audited snapshot.
- A real call path reaches the code.
- Frequency and input scale are stated rather than implied.
- Existing guards, bounds, caches, framework behavior, and background work are credited.
- The recommendation explains why it should help and when it should be rejected.
- Code quality without a credible performance effect is excluded.
- One root cause does not receive multiple priority slots merely because it appears in several layers.

Stable IDs never change when severity, confidence, or priority changes. A merged finding keeps the strongest root ID and records retired IDs as supporting evidence.
