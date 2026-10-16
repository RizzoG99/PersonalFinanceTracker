# PR #230 — final integration verification

Date: 2026-10-16. Branch: `chore/performance-baselines`. No merge or release is authorized by this report.

## Source and isolation

The candidate includes `main` at `cc86f16305c1252c909a937caa92afda75150d8f`
(merge `e8df73f`), PERF-111 at `3402878`, and retained receipt profiling/evidence
at `ae6d7c4`. The receipt single-pass experiment was rejected and removed before
this integration: the production two-render pipeline remains. The accepted
PERF-301 stopping decision is not a claim of universal device performance or OCR accuracy.

Verification used a separate detached checkout at `ae6d7c4`, with only the
test correction below applied. The app, standard shared scheme and build script
come from committed source; the dirty TEST identity/configuration, local launch
overrides, raw traces/photos and unrelated audit rewrites were absent. The final
documentation/test commit contains the exact test bytes validated here:

- `ImportCategoryNameTests.swift` SHA-256:
  `08e9547602fbb6b9f2cf61de43c61b4f611411c1d62e36c7711859ca0e995379`.

Dedicated device: `pft-pr230-final-verification`, iPhone 17, arm64 Simulator,
iOS 27.0 (`24A434`), UDID `730B2DBF-25B1-44D9-97F5-FE14AD3DFCD5`.
Only this disposable simulator's app was uninstalled for UI checks. No personal
device, personal store or other worktree's simulator was reset.

## Validation results

| Check | Result | Local evidence |
| --- | --- | --- |
| Complete standard unit target, English | **822 passed, 0 failed, 14 skipped**; 892 passing executions including parameters | `.build/pr230-final/full-unit-final-summary.json`, `full-unit-final-tree.json`; isolated `.build/FullUnit-final.xcresult` |
| Italian category display/picker/matching and search | **20 passed, 0 failed, 0 skipped** | `.build/pr230-final/italian-summary.json`; isolated `.build/Italian-final.xcresult` |
| Standalone opt-in actual recognizer boundary, Release-TEST | **1 passed, 0 failed, 0 skipped** | `.build/pr230-final/isolated-recognizer-summary.json`; uses preserved local TEST configuration |
| UI navigation, light appearance, English/Ireland | **1 passed, 0 failed, 0 skipped**; 9 screenshots | `.build/pr230-final/ui-light-summary.json`; isolated `.build/UI-light-final.xcresult`, `.build/ui-review/light/` |
| UI navigation, dark appearance, English/Ireland | **1 passed, 0 failed, 0 skipped**; 9 screenshots | `.build/pr230-final/ui-dark-summary.json`; isolated `.build/UI-dark-final.xcresult`, `.build/ui-review/dark/` |
| Standard Release Simulator build | **Passed**, compiler warnings remain | `.build/pr230-final/release-final.log`, `release-final-result.json` |
| Profiling analyzer Python tests | **11 passed** | Existing analyzer test suite |
| Python syntax, localization JSON, project and release notes | Passed; 800 localization entries without duplicate keys; project plist valid | Analyzer/PERF-112/PERF-301 scripts, `plutil -lint`, `scripts/xcb check-notes` |
| Whitespace and graph maintenance | `git diff --check` passed; Graphify updated with Git status unchanged | Original worktree |

The full English result contains 836 test functions. Its 14 explicit skips are:
4 Italian-only checks (all exercised by the Italian run), 4 opt-in analytics/bulk
checks requiring the local TEST/widget environment, 2 opt-in receipt timing checks,
2 private-corpus OCR tests, the acquired-photo crop-parity diagnostic, and the
acquired-photo field-accuracy diagnostic. These are not counted as passing.
Earlier dedicated benchmark/widget/receipt results remain historical evidence
with their own provenance; this standard suite does not rerun every opt-in gate.

The supplied-photo OCR field-accuracy replay is known red and remains separate:
#244 tracks total selection and #245 tracks merchant-heading/accent fidelity.
An opt-in skip does not resolve those failures. PERF-301 #241 and Insights #235
remain open; no automatic closure is introduced for either.

### Why the category-repair test changed

The first isolated full run produced 821 passes, one failure and 14 skips. The
only failure was the five-second wall-time assertion around
`repairImportedCategoryNames`: 10.792 seconds. A targeted run of all seven
`ImportCategoryNameTests` passed. A complete control run at `main` passed
(770 passed, 0 failed, 6 skipped). Repeating the full candidate reproduced the
same single failure at 15.565 seconds; the previous onboarding failures did not
recur (all 14 `FeatureDiscoveryCoordinatorTests` passed).

A temporary probe measured the actual synchronous actor method, with no await
inside its interval: **10,729.41 ms wall, 1,638.73 ms executing-thread CPU**;
the entire call took 10,729.51 ms. The long interval was inside the synchronous
routine, not initial actor-queue wait. Storage/scheduling contention contributes
to wall time; the probe does not identify its exact split or establish that
production end-to-end latency is below five seconds. The repair implementation
and original test were byte-identical to `main`; no production repair fix was made.

The test retains its five-second numeric budget as a **thread CPU** check, measured
inside a test-only synchronous actor extension with `CLOCK_THREAD_CPUTIME_ID`.
It also observes synchronous `ModelContext.didSave` notifications for only its
fixture container and asserts exactly one save, including after an idempotent
repeat. Existing 5,000-row correctness and unlinked-row checks remain. This
directly guards the save-amplification contract and bounds executing-thread work.
It deliberately replaces the wall-latency contract; it is not a device latency
guarantee or proof against every slow algorithm. No threshold was increased.
The full suite then passed with the results above. Temporary probes were removed.

Historical summaries, test trees, the probe signal and the original test copy
are retained locally in `.build/pr230-final/`. They are diagnostic evidence,
not additional passing validations.

### UI scope and limits

The existing screenshot walk completed onboarding and navigated Home, Activity,
Plan/budgets, Insights, the add form, Settings, categories and import/export settings.
It uses ordinary sample data, not the 5,000-row performance fixture. Its final
search step is conditional: no `03-activity-search.png` was produced in either
pass, so typing/search interaction is **not verified** by those passing results.
Both runs record `Invalid frame dimension (negative or non-finite)` as a
runtime warning. The tests pass despite that warning; no clean runtime-warning
or complete visual-quality claim is made. The earlier canceled setup attempt
is excluded from validation.

Home, Activity and Insights screenshots were inspected in both appearances for
surface/color consistency and obvious clipping at the default compact size.
This limited inspection does not complete the manual quality gates below.

The checks do not establish frame latency, energy, memory peaks or on-device
bulk-edit speed. Manual verification remains open for iPad/wide and landscape,
accessibility Dynamic Type, VoiceOver, the pagination/loading/error/empty states,
keyboard/search interaction, and camera rotation on the integrated physical build.
The available Simulator runtime is iOS 27; this is not an iOS 26 runtime pass.
Existing camera concurrency warnings were not suppressed or addressed here.

## Preservation and publication boundary

The initial snapshot covers 63 dirty files. **61 remain byte-identical**. Only
`ReceiptRecognitionBoundaryTests.swift` and its PERF-301 report received the
scoped opt-in guard/documentation change: the process-global recorder diagnostic
must run alone with `PFT_RECEIPT_RECOGNITION_BASELINE=1` and the TEST bundle ID.
`ImportCategoryNameTests.swift` was initially clean and is the additional test-only
change described above. The receipt contributions were committed selectively;
the summary received only a staged acceptance block. Broader summary/manifest/
roadmap edits and the TEST variant remain dirty and unpublished.

No raw receipt photos, traces, personal stores or build artifacts are committed.
The eight redacted PERF-301 reports include the rejected candidate explicitly as
historical evidence. Do not interpret their presence as shipping that algorithm.
No persistent schema change is introduced. GitHub checks, when absent, are not
reported as CI success. Publication prepares PR #230 for human review; it does
not merge, archive or upload the app.
