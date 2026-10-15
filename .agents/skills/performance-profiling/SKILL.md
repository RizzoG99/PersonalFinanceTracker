---
name: performance-profiling
description: Bound a specific iOS performance complaint, instrument its interaction, guide manual device profiling, and analyze saved Instruments runs with an explicit stopping criterion. Use for freezes, slow search, or before/after profiling; use performance-audit for a repository-wide audit.
---

# Performance Profiling

Turn a perceived slowdown into a bounded, repeatable decision: fix a demonstrated cause,
accept an observed limit, or request one specific missing measurement. Use the project's
diagnosing-bugs workflow for uncertain causes and swiftui-pro when changing SwiftUI.

## 1. Agree what would justify more work

Inspect existing source, traces and reports before asking questions. Resolve only the
missing facts that change the experiment: exact gesture and visible symptom, first vs
repeated occurrence, device/build, dataset scale, and whether the problem disrupts use.
For search distinguish keyboard appearance, typing, the intended debounce, result
computation, and result presentation. A whole-recording CPU total cannot answer all five.

Record the worktree/commit plus dirty-state scope, trigger, observation window, success
criterion, and investigation budget. A useful default is one baseline, one causally
motivated change, and one comparable follow-up before reassessing. Set a criterion with
the user when no product latency budget exists; a sample weight is not a freeze duration.

Stop structural optimization when the complaint is acceptable on the target device or
the next change has no measurable predicted benefit. When an experiment shows no clear
improvement, report that result and retain correctness fixes; do not widen the architecture
to pursue an interesting stack. Ask for additional profiling only when its result would
change the next decision. Respect a request to stop at an analysis or PR.

## 2. Place markers around the real work

Inspect opt-in PerformanceAuditRecorder instrumentation before adding markers. Use
static names, unique interval IDs, and counts/revisions/generations without financial
contents. Keep instrumentation settings equivalent between compared builds.

- Emit an interaction-request event before changing selection/query state. An onChange
  or onAppear can run after view construction; verify ordering in the captured trace.
- Distinguish request, debounce expiry, compute start/end, publication, superseded work,
  and appearance. Appearance/body evaluation is not evidence that a frame was presented.
- Split synchronous SwiftData fetch and snapshot mapping; record their actual executing
  thread. A synchronous interval's thread is meaningful; an async loader's start/end
  thread does not describe its full CPU execution or time suspended.
- Include the owning generation and input/result counts so stale commits and duplicated
  loads can be detected. Prefer one boundary marker to a log per transaction.

If the first relevant body or computation precedes the supposed interaction marker,
include that earlier segment in analysis and repair the marker before claiming latency.
Attribute CPU through named stacks, distinguishing app computation, framework layout,
metadata initialization, actor queueing and background work. `$main()` as the nearest
app frame does not make framework work entry-point self time.

## 3. Give the user an executable capture protocol

Read [references/device-capture.md](references/device-capture.md) when preparing a new
recording. Name the device and build, data, launch arguments, exact actions, recording
length, instruments, save path, and acceptance observation. The user controls Instruments
and the device unless they explicitly delegate that operation.

## 4. Analyze the saved artifact

Read [references/trace-analysis.md](references/trace-analysis.md). Inspect the trace TOC
and select the requested run explicitly; one `.trace` can contain several runs. Check
platform, timestamp, app binary and required tables. A device-looking filename is not
device evidence. A missing/unsaved run is a missing input, not the preceding run.

Use `scripts/analyze_trace.py inspect TRACE` and `scripts/analyze_trace.py analyze TRACE
--run N ...` for reproducible JSON summaries. It exports existing recordings only. Match
marker windows to CPU samples and keep any pre-marker work visible. For an unmarked
search segment, start with the user-specified tail, then use filter/group and CPU bursts;
report that key-to-result latency is unavailable without query/commit markers.

## 5. Validate and hand off

Use targeted behavioral tests for cache freshness, stale-result suppression and coalescing;
use a comparable recording for responsiveness. Change one causal variable at a time.
Follow AGENTS.md for build/test commands and report every unrun physical-device or UI check.

Hand off: artifact/run provenance, exact windows, sampled CPU weights and top stacks,
interval/count evidence, verified vs inferred causes, before/after comparability, user
observation, and a stop/continue recommendation. Keep raw traces/logs local and ignored;
commit only redacted measurements. PR descriptions must not turn a structural improvement
or a simulator result into a proven physical-device latency fix.
