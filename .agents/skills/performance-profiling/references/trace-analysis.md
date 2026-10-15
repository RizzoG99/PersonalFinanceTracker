# Analyze existing Instruments runs

## Inspect before selecting

From the requested worktree:

```sh
rtk python3 .agents/skills/performance-profiling/scripts/analyze_trace.py inspect path/to/capture.trace
```

The helper calls `rtk proxy xcrun xctrace export` without recording, launching, or controlling
the app/device. It prints run numbers, dates, platform, process and table availability.
Select the requested run explicitly. If it is absent, ask the user to save it or identify
the other file; continue independent authorized work while waiting.

If export fails because Instruments cannot write its analysis cache, retry the same read
through the environment's normal escalation mechanism. Do not change HOME or cache paths
to evade permissions. Exports can write tool caches even though the trace is only read.

## Windows

```sh
# A verified interaction boundary, including a half-second lead-in
rtk python3 .agents/skills/performance-profiling/scripts/analyze_trace.py analyze path/to/capture.trace --run 2 --marker Activity.tab.selected --pre 0.5 --duration 1

# A user-described final ten-second search segment, using TOC recording duration
rtk python3 .agents/skills/performance-profiling/scripts/analyze_trace.py analyze path/to/capture.trace --run 3 --tail 10

# An explicit interval after inspecting the first summary
rtk python3 .agents/skills/performance-profiling/scripts/analyze_trace.py analyze path/to/capture.trace --run 3 --start 35 --duration 2 --bucket 0.25
```

`--marker` uses a PFT event's recorded time. Repeated occurrences require `--occurrence N`.
`--pre` extends the start before that anchor; `--duration` extends the end after it.
For `--tail`, the end comes from the selected run's recording duration, not its last CPU
sample. The helper refuses missing runs/markers and distinguishes missing data from zero
observed activity. It resolves XML `id`/`ref` links and counts samples without stacks as
unknown instead of silently dropping their weight.

Check `cpu_evidence_available`: an empty CPU export has a null sampled weight, whereas a
populated export with no matching samples in the selected window has zero observed weight.
Interval summaries retain begin and end metadata separately, including generation/count
details that may appear on only one boundary.

Check whether the recorded boundary preceded the work. A TabView onChange can arrive after
body evaluation and metadata/layout work. Analyze a lead-in alongside the nominal window;
for future captures place the request marker in the binding setter before state mutation.
Keep the old marker name/meaning documented when adding a new earlier boundary.

## Interpretation

- `main_sampled_ms` is summed Time Profiler sample weight. It is not wall-clock freeze
  duration, key-to-result latency, or the percentage of frames missed.
- `leaf_top` is sampled self weight. `inclusive_top` counts each named frame at most once
  per sample; recursive stack occurrences do not multiply its weight. Inclusive rows
  overlap and must not be added together.
- `nearest_app_top` identifies the nearest app frame in a stack, not that frame's self
  weight. `$main()` often just anchors SwiftUI/UIKit/runtime stacks.
- Use half-second CPU buckets to locate bursts, then narrow around query/debounce,
  filter/group, commit and presentation markers. A 250 ms debounce is intentional
  scheduling time, not 250 ms of CPU. Filtering off-main does not prove publication/layout
  is cheap; include both phases and generation correctness.
- Compare cache/store sources and materialization generations. Synchronous fetch/map
  markers on the main thread prove where that work ran, but establish causality for an
  interaction only if they overlap its complete window.
- An async loader interval includes suspension, executor scheduling and any awaited work.
  A changed completion boundary makes wall durations incomparable until normalized.
- Check overlap with widget, backup, maintenance and lifecycle intervals. Coalescing counts
  and correctness tests can establish structural wins separately from latency evidence.

Keep provenance, exact windows, counts, weights, hot stacks, user observation and remaining
uncertainty in a redacted summary. Raw traces and logs stay in ignored local storage. Verify
before claiming latency is fixed; otherwise state which measured stage improved and which
requires a device observation. Use the agreed stopping criterion after each experiment.
