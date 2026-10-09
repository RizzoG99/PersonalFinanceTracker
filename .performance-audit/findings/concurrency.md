# WS-RUNTIME — Concurrency and Task Lifecycle

## Scope and method

Static screening covered receipt-flow tasks, cancellation boundaries, actor hops, the undo timer, notification sequences, and `Task.detached` use in `TransactionListViewModel` plus its directly invoked Activity grouper. Two findings were accepted. The undo timer checks cancellation before commit, notification publishers are SwiftUI-owned, and camera frame backpressure is explicit; those paths were not promoted to findings.

## PERF-303: Search debounce cancellation still launches the expensive filter pipeline

Severity:
High

Confidence:
Strong Evidence

Category:
Concurrency

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift`
- Lines: 110-120, 240-264, 448-453
- Symbol: `TransactionListViewModel.searchText`, `filters`, `doFilterItemBySearchText()`, `clearSearch()`

Description:
Each search-text change cancels the previous debounce task, but that task suppresses the `CancellationError` from `Task.sleep` and immediately continues into the full transaction filter. Rapid typing therefore executes work for canceled debounce tasks instead of coalescing it. `clearSearch()` additionally mutates both observed properties and launches an explicit third filter task.

Root Cause:
`try? await Task.sleep(...)` converts cancellation into normal control flow and there is no cancellation guard before filtering. Filter changes use untracked tasks, and `clearSearch()` redundantly schedules work already triggered by both property observers.

Trigger:
Type rapidly in Activity search, adjust filters in quick succession, or clear an active search/filter.

Impact:
With a multi-year store, one user gesture can start several full-array scans. Every result assignment also recomputes category counts/totals and starts grouping, amplifying CPU use and increasing the chance of stale results landing after newer input.

Evidence:
The canceled sleep at lines 113-115 is explicitly swallowed. `doFilterItemBySearchText()` snapshots and filters the entire transaction array at lines 247-261. `clearSearch()` triggers `searchText.didSet`, `filters.didSet`, and a third explicit task at lines 448-453. This execution pattern is definite; duration and energy cost are not measured.

Recommended Optimization:
Exit on `CancellationError` (or guard `!Task.isCancelled`) before filtering, use one owned task/generation for both text and filter changes, and remove the explicit duplicate call from `clearSearch()`. Commit results only if their generation still matches current inputs.

Trade-offs:
Filter-chip changes may need immediate rather than debounced execution. A single scheduler should preserve that distinction while still canceling superseded work.

Validation:
Add signposts/counters around filter starts and committed results. Type a known sequence against a realistic thousands-row fixture and verify only the final text search executes after the debounce, clear performs one derivation, the result matches the latest inputs, and main-thread responsiveness improves in Time Profiler.

Estimated Effort:
Small

## PERF-304: Detached filter and grouping jobs outlive the tasks that claim to cancel them

Severity:
Medium

Confidence:
Strong Evidence

Category:
Concurrency

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift`
- Lines: 240-284
- Symbol: `doFilterItemBySearchText()`, `updateGroupedItems()`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/ActivityRow.swift`
- Lines: 107-151
- Symbol: `ActivityRowGrouper.group(_:travels:includeEmpty:)`

Description:
Filtering and grouping are launched with `Task.detached`. Canceling the outer debounce/grouping task does not cancel those detached jobs. Grouping discards a canceled result only after all iteration, dictionary construction, date formatting, and sorting have finished; filtering does not check cancellation before assigning its result.

Root Cause:
Detached tasks sever structured cancellation. The synchronous filter and grouper also contain no cooperative cancellation checkpoints or generation check at commit time.

Trigger:
Rapid search/filter changes, a refresh that updates travels and transactions close together, or any state sequence that calls `updateGroupedItems()` again before its prior detached job completes.

Impact:
Superseded O(n) filtering/grouping and O(d log d) section sorting continue consuming CPU concurrently. A superseded filter result can overwrite newer state; canceled grouping avoids the stale write but still pays the full computation cost.

Evidence:
The outer grouping task is canceled at line 277, but the work created at lines 279-281 is detached. The cancellation guard is only after `.value`. Filtering similarly awaits an independent detached task at lines 250-261 and assigns unconditionally at line 263. The grouper traverses all items and sorts sections/rows at `ActivityRow.swift` lines 112-150.

Recommended Optimization:
Use structured off-main execution whose child inherits cancellation, or retain/cancel the actual worker task. Add generation checks before committing both filter and grouping results and cooperative cancellation inside large traversals if realistic datasets justify it.

Trade-offs:
Moving synchronous CPU work while preserving actor isolation and `Sendable` snapshots needs care. Cancellation checks inside tight loops add small overhead; benchmark realistic sizes before making them granular.

Validation:
Instrument worker start/cancel/finish and record CPU time during rapid input with thousands of transactions. Verify superseded jobs stop early, only the latest generation commits, and final grouping remains deterministic.

Estimated Effort:
Medium

## Evidence limitations

- No Swift Concurrency Instruments trace or CPU profile was recorded.
- Findings establish redundant/reachable work, not its wall-clock cost on supported devices.
- Import parsing detached tasks were screened but left to WS-DATA unless focused validation shows a cancellation-related user impact.
