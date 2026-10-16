# Activity search — first physical-device recording

> Publication note — 2026-10-16: Historical physical-device recording, analyzed at the source recorded below. It is not an updated recording of the integrated PR. The decision to defer further search optimization remains unchanged; see [the publication checkpoint](../summary.md).

Status: saved run analyzed; typing lag reported by the user; an app-owned root cause and key-to-visible-result latency are not yet established. No optimization, UI change, instrumentation change, commit or external PR update was made during this analysis.

## Provenance

- Artifact: `traces/Activity-search-5k-PFT-TEST-iPhone-r1.trace`, explicitly selected **run 1**, the only saved run.
- Recorded 2026-10-15 at **23:28:56.950 +02:00**, duration **65.820671 s**.
- TOC confirms a physical **iPhone 14 Pro Max**, **iOS 27.0.1 (24A446)**, process `PersonalFinanceTraker`, PID 23775.
- Native signpost subsystem is `rizzoG99.PersonalFinanceTraker.test`, confirming the isolated TEST identity. App signpost return locations identify binary UUID **B6C1AD37-8471-3691-9142-86E253C9407D**.
- The intended Profile configuration in the TEST scheme is Release-TEST. The trace does not independently encode a Git revision or build-configuration name; optimized/specialized symbols alone do not prove the configuration. Current analysis checkout: `.worktrees/performance-baselines`, branch `chore/performance-baselines`, HEAD `d1b7f5b48a0bf2ee882639cfbc3171fe7d826eb0`, with existing dirty variant/configuration/source/test/documentation work. This identifies the analysis checkout, not a proven recorded commit.
- Recorder metadata confirms **5,000 transactions**, no travels in the grouping inputs, and a visible first page of **200 rows in 68 date sections** on entering Activity. Full backing groups contain 1,826 dates. The 5-year fixture differs from the earlier 365-date/two-category ViewModel benchmark.
- Thermal state was **Nominal for the entire run**. Low Power Mode, display refresh mode and exact language/keyboard settings were not established.
- User observation: **slight lag during typing, no perceived freeze**. This is one exploratory recording, not a repeated latency distribution or a before/after comparison. No accepted numeric product latency budget is established.

## Extraction and a format distinction

The standard helper was run with `inspect`, then `analyze ... --run 1 --start 0 --duration 65.820671 --bucket 0.5`. Instruments analysis-cache access required normal escalation. Only existing recordings were exported; no device/app/profiler was controlled.

The `os-log` export has **zero rows**, so the helper's `pft_events_available=false` means no PFT logger messages in that table. It does **not** mean instrumentation was disabled. Native **OSSignpostIntervals contains 114 app intervals**, and **PointsOfInterestEvents contains 19 app events**. A local analysis probe resolves the native XML id/ref links and extracts start/duration, owning process, names, metadata and beginning/ending threads from those tables. The skill helper and production recorder were not changed.

Time Profiler contains **5,620 samples**, including **3,859 main-thread samples weighted 1 ms each** over the full recording. No selected main-thread sample is missing its stack or weight. These sample weights are aggregate observed time, not a freeze duration, per-key latency, or a count of missed frames. Inclusive stack weights overlap and must not be added together. `$main()` as nearest app frame is a framework-stack anchor, not entry-point self time.

Raw XML exports, helper output and the local probe remain ignored under `.build/activity-search-device-r1-*` and `.build/analyze-activity-search-device.py`. Only the redacted Markdown/JSON measurement pair is added to the existing WIP.

## Bound the stages first

| Stage | Evidence in this recording | Boundary limit |
| --- | --- | --- |
| Keyboard activation | Search field `becomeFirstResponder`, input-view initialization and keyboard layout stacks at 21.337–21.700 s | Identified from stacks; no app keyboard-request or first-key marker |
| Typing | Keyboard input/task stacks and Activity body updates around 32.5–35.8 and 41.0–44.5 s | Window labels are inferred from stacks/protocol, not query text; user reports lag here |
| Debounce | Current source schedules 250 ms after `searchText.didSet`; worker starts are marked | Query requests and debounce expiry are not marked; actual debounce/scheduler delay is unmeasured |
| Filter | Seven `Activity.filter` intervals, all with 5,000 inputs and `main=0` | No query/generation IDs; no recorded text contents |
| Derived state | `Activity.derivedFilters` covers categories/icons/totals on MainActor | Not the complete `filteredItems` assignment or all SwiftUI invalidation |
| Group / publication | Detached `Activity.group`, then `Activity.group.publish` on MainActor | Assignment duration is not subsequent layout/render duration |
| Presentation | Parent-body/page intervals and sampled UIKit/SwiftUI list-update stacks | No presented-frame marker or exact key-to-pixel timing |

## Timeline and computation

- **1.957906–2.007316 s:** synchronous SwiftData fetch, **49.409 ms**, main thread.
- **2.007321–2.054805 s:** synchronous snapshot mapping, **47.484 ms**, main thread; 5,000 snapshots. All four later repository reads are cache hits; the last ends at 2.404906 s.
- Bootstrap, Activity/Dashboard loads and Habit/Safe-to-Spend refresh/write work settle by **2.406337 s**. No repository fetch, load or widget/maintenance interval overlaps the later typing windows.
- **17.356746 s:** first Activity body begins, **107.528 ms before** `Activity.tab.selected` at **17.464274 s**. That onChange marker is late and cannot be used as an exact tap/request boundary. Both selection-time load requests are skipped.
- **21.337–21.700 s:** keyboard/search-field activation stacks. An unfiltered derived/group refresh follows at 21.867–21.906 s, with no text-filter worker.
- **33.120–44.284 s:** seven nonoverlapping filter intervals. The first four subsequent derived-state records have 5,000 results; the last three have zero. Counts cannot identify individual characters or prove freshness/generation correctness.
- **52.805–52.872 s:** an unfiltered refresh restores 5,000 items, consistent with query clearing. A second unfiltered refresh occurs at 55.661–55.709 s. The exact gesture producing that latter refresh is unmarked; no further filter runs are recorded.

| Stage after 30 s | Count | Median wall time | Min–max | Executing thread |
| --- | ---: | ---: | ---: | --- |
| Filter, 5,000 inputs | 7 | 26.502 ms | 24.000–60.684 ms | Background, synchronous begin/end on same worker |
| Group, including empty results and clear | 9 | 37.267 ms | 0.010–42.090 ms | Background |
| Derived filters, including clear | 9 | 4.256 ms | 0.010–12.161 ms | Main |
| Group publication assignment | 9 | 0.340 ms | 0.014–0.457 ms | Main |
| Activity parent body | 25 | 0.198 ms | 0.069–0.355 ms | Main |
| Page preparation | 25 | 0.041 ms | 0.004–0.135 ms | Main |

The largest post-bootstrap group-publication assignment, including keyboard activation before 30 s, is **0.534 ms**. Short publication/body markers do not imply that list diffing, layout and rendering are equally short.

The elapsed span from each filter start to the end of the next following group publication is **51.272–77.234 ms** (median **70.600 ms**). These are temporal pairings of serialized intervals, not generation-linked query measurements. They exclude the intended debounce, preceding input processing and subsequent frame presentation; they are not key-to-result latency.

## Main-thread work while typing

| Exact window | Main-thread sampled weight | Selected inclusive stacks |
| --- | ---: | --- |
| 32.500–35.800 s, first typing cluster | **554 ms** | Keyboard task queue 167 ms; `GraphHost.flushTransactions()` 151 ms; `UpdateCollectionViewListCoordinator.updateValue()` 65 ms |
| **34.000–35.200 s**, within that cluster | **369 ms** | Keyboard task queue 124 ms; graph transaction flushing 111 ms; list coordinator update 47 ms; collection update application 36 ms |
| 41.000–44.500 s, extension cluster | **285 ms** | Keyboard task queue 101 ms; graph transaction flushing 57 ms; collection update application 23 ms |
| 51.000–53.500 s, clear candidate | **323 ms** | Core Animation transaction commit 73 ms; collection layout 32 ms; keyboard task queue 51 ms |

The **34.000–35.200 s window contains eight parent-body/page evaluations but zero filter, grouping, derived-filter or group-publication intervals**. The preceding group publication ends at 33.587562 s; the next filter starts at 35.416115 s. Substantial input/UI processing therefore occurs while no result computation/publication is active. This bounds an important part of the complaint before attributing it to the search engine. It does not isolate which SwiftUI dependency, keyboard operation or framework update causes a delayed frame.

In this window, 353 of 369 ms has `$main()` as nearest app frame. Named app work includes row identity/value handling and the Activity page/body path, mostly at 1–2 ms sampled weights. The short parent-body intervals alone are not the observed CPU cost; framework graph/list work extends beyond body construction. A framework-heavy stack does not prove the app cannot influence that work, and a list coordinator stack does not alone justify replacing List or rewriting the view model.

## Native potential-hang records

Instruments records two **Microhang** candidates:

| Window | Classified wall duration | Main sampled weight | Attribution available |
| --- | ---: | ---: | --- |
| 17.346499–17.613072 s | 266.573 ms | 222 ms | Activity first-presentation/SwiftUI work; includes work before late selection marker |
| 21.337350–21.699810 s | 362.460 ms | 177 ms | `UISearchTextField.becomeFirstResponder`, keyboard focus/input-view initialization/layout |

Neither overlaps a filter interval. Neither is in the later typing clusters. The `hang-risks` table is empty. These are profiler classifications, not a claim that the user perceived a freeze; the user's report remains slight typing lag without a freeze. No native potential-hang record during typing does not exclude missed frames or short input delays.

## Decision and next useful experiment

Verified: filter/group execution is off-main; publication assignments are short; no store reload contaminates typing; and notable main-thread input/SwiftUI list-update work exists between result computations. **The trace does not establish an app-owned root cause or justify a filtering/debounce optimization.** No structural change is applied.

The recorded human loop is: show keyboard, type a query, pause, extend, pause, clear, save the trace; the user reports mild typing lag. It has run once, but is not yet a deterministic, minimized per-key/frame pass/fail loop. The diagnosing-bugs gate for a causal UI fix remains open. Existing simulator/ViewModel timings cannot be treated as a comparable device before/after baseline.

If this mild lag is acceptable in everyday use, stop here. If it warrants further work, the next bounded step is **query-to-UI instrumentation**, followed by the same physical-device sequence: request/generation before query mutation, debounce expiry, filter completion, filtered-state and grouped-state publication, plus a frame/input-latency observation. Then test one specific prediction about list invalidation during typing, keeping fixture, keyboard, build, debounce and filtering behavior constant. Do not request another unmarked whole-recording CPU total or refactor around an interesting framework stack. At most one measured causal change and one comparable follow-up before reassessing.

This analysis changed no app/UI code and reran no app tests. Physical-device responsiveness evidence is the supplied run; light/dark, compact/wide, Dynamic Type, VoiceOver and additional device runs were not executed. All pre-existing dirty files are preserved; raw traces/exports stay local and ignored.
