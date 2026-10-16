# PERF-301 / #241 — receipt image processing baseline

## Separate OCR correctness tickets — 2026-10-16

- [#244](https://github.com/RizzoG99/PersonalFinanceTracker/issues/244): fixture
  `F67C00E3-6578-4B2D-B466-627561629733` selects the printed tax instead of the recognized total.
- [#245](https://github.com/RizzoG99/PersonalFinanceTracker/issues/245): fixture
  `60593A10-CFAF-4C61-A369-A7A02925D21B` selects a damaged table-heading word instead of the
  merchant. Four other inputs differ only by an accent; distinguish their fidelity policy
  from the semantically wrong merchant rather than counting five equivalent failures.

Both issues are in iOS Native, Todo / Analyzed / Transactions, with the existing executable
private-corpus repro, source/configuration provenance, opaque input IDs/hashes, local
expected/actual artifact locations, limits and completion criteria. They do not expose raw
receipt data. The original baseline and final restored OCR replay already reproduce these
failures; the final `final-ocr.xcresult` summary was rechecked (one failed function, zero skips).
No new test execution or root-cause claim is made in this tracking update. A plain checkout
cannot run these examples without the ignored corpus and WIP harness; a minimized sanitized
regression is still needed before fixing either symptom. No date issue was observed (8/8).
PERF-301 remains stopped as accepted; these correctness issues do not enter PR #230's code scope.

## Accepted stop — 2026-10-16

The user accepts retaining the restored production pipeline under the measured/tested conditions;
no further optimization is scheduled. This accepts the bounded outcome, not universal device
performance or perfect OCR accuracy. The preventive single-pass candidate was discarded because
one real input changed crop/OCR pixels and recognized lines despite synthetic CPU savings.
See [recorded acceptance, verified conditions, limitations and reopening gate](PERF-301-single-pass-experiment.md#user-acceptance--2026-10-16).
Audit ID PERF-301 remains GitHub #241; disposition is `BASELINE_MEASURED_STOP_IN_SCOPE`.

## Authorized single-pass follow-up — rejected, 2026-10-16

The user authorized one preventive rendering experiment on the updated main base. It was
implemented and measured, then **reverted**: rotated valid-crop CPU falls 22–48% in the local
synthetic harness, but one of eight real crop/OCR inputs changes pixels and its OCR line list
changes. Key total/date/merchant fields remain at the existing red baseline; this is not a claim
of a newly wrong total. The exact pre-experiment camera source is restored. Final geometry/form/
parser/parity validation passes 122 functions / 148 executions with zero skips; all eight real
crop and prepared-OCR pixel comparisons pass after rollback. See the
[experiment report](PERF-301-single-pass-experiment.md) and
[redacted measurements](PERF-301-single-pass-experiment.json). No further generic device
recording is requested for the rejected candidate. Earlier checkpoint sections below retain
their original scope/provenance; accepted analytics stops and PERF-303 deferral are unchanged.

## Main synchronization — 2026-10-16

At the user's request, fetched `origin/main` and merged `cc86f16` into this worktree as
`e8df73fada945da6238f3ec9baac7f71ae70c24b` (parents `3402878`, `cc86f16`). This retains the
six existing branch commits and imports category fixes #238/#240 plus the scanner rotation
fix **#243 / #242**. No push or remote PR update was performed.

The merge reconciles guarded category saves and rename propagation, and preserves the existing
iPhone/iPad bootstrap gates while including category-name repair and backup. The restored
camera instrumentation exports/uses only the effective quad whose angle matches the captured
photo; unsupported rotation or a stale quad retains #243's full-frame fallback. No rendering,
OCR-policy, resolution, executor or Sendable workaround was introduced.

Before synchronization, all 59 WIP files were copied/fingerprinted under ignored
`.build/main-sync/20261016-155647/` and saved in a retained local stash. Immediately after
restoration, **57/59 were byte-identical**; only the changelog (both sets of notes retained)
and camera instrumentation needed integration with main. The TEST project/settings, scripts/xcb
and all other WIP were preserved; the main checkout's six WIP files remained unchanged.
An intervening project-group reorder was saved separately and reconciled; the final project
file is byte-identical to its pre-sync WIP. The original empty index was restored empty.

Validation and source identity are in [the synchronization record](PERF-301-main-sync.json).
Release-TEST targeted regression passed **235 test functions / 254 executions**, zero failures;
all **14 requested suites** appear in the xcresult. Two Italian-only tests were skipped in en_US;
the follow-up `CategoryDisplayNameTests` run in it_IT passed **all five**, zero skips/failures.
The isolated eight-photo replay still fails with the same six assertions, with total/date/merchant
results unchanged on all eight inputs and all eight crop JPEG attachments byte-identical to the
pre-sync diagnostic run. These are existing baseline failures, not green accuracy validation or
new merge regressions. Raw results stay under ignored `.build/main-sync/20261016-155647/`:
`regressions.xcresult`, `category-italian.xcresult`, `device-fixture-replay.xcresult`.
The final index is empty; `git diff --check` passes; graphify updated without changing Git status.
Physical rotation, orientation lock, light/dark, compact/wide layouts, Dynamic Type and VoiceOver
were not retested here; the device remains user-controlled. Earlier device timings/VM samples
below belong to the pre-#243 build and are **historical**, not a measured post-fix baseline.
Saved original/quad replays validate image processing, not the new live-camera rotation path.
Any rendering experiment must use this updated base and a comparable new pre-change measure.
The accepted PERF-201/PERF-112/PERF-111 stops and PERF-303 deferral remain unchanged.
The following baseline provenance and preservation statements describe their earlier checkpoints.

## Decision and provenance

**Baseline only; no image-processing optimization. Device runs 3 and 4 are analyzed below.
Run 4 adds native VM Tracker samples; true transient peak/physical footprint remain unverified.
Eight exported real photos have now been replayed: the correctness oracle is red, with one
incorrect total and merchant differences documented below. No further broad recording is requested.**
Audit ID **PERF-301** is tracked by [GitHub issue #241](https://github.com/RizzoG99/PersonalFinanceTracker/issues/241),
added to the [iOS Native project](https://github.com/users/RizzoG99/projects/4).
PR context: [#230](https://github.com/RizzoG99/PersonalFinanceTracker/pull/230).

Worktree `.worktrees/performance-baselines`, branch `chore/performance-baselines`,
initial HEAD `34028786effbc9c118d545fa05eaedff9e5549f3`, 2026-10-16.
43 pre-existing dirty/untracked file fingerprints are saved locally in
`.build/perf301/initial-wip.json`. No commit, push, merge, release or store reset.
The TEST configuration and `scripts/xcb` are preserved pre-existing WIP.
Xcode 27.0 (27A266a), Swift 6 toolchain **with the actual project's Swift 5 language mode**;
no concurrency-setting migration or new unchecked-sendable conformance.

PERF-201, PERF-112 and PERF-111/#235 remain stopped in their accepted scopes.
The current PERF-111 report at HEAD supersedes stale ownership descriptions in
manifest/roadmap; those references are reconciled, without changing their accepted code.
PERF-303/#237 remains deferred. Original audit findings retain their historical evidence.

### Contribution boundary for PR #230

This follow-up consists only of receipt boundary instrumentation, internal test seams,
synthetic/local-fixture harnesses, receipt summary/native VM-archive extraction scripts and this report/JSON,
plus scoped additions to the existing summary and status reconciliation in manifest/roadmap.
The recorder gains optional metadata on its existing synchronous measurement API.
There is no public API, persistent schema, camera lifecycle, OCR-pass policy, executor,
rendering algorithm, recognition resolution, visual hierarchy or styling change.
No changelog entry is needed for this measurement-only addition.
The existing TEST/widget/configuration WIP, broader audit rewrite and unrelated reports
are excluded from this contribution. Future optimization requires a separate evidence-backed
scope decision before changing code; it is not bundled automatically into #230.

## Physical iPhone follow-up — saved run 3, 2026-10-16

The user tested a near-full receipt, a distant receipt, a partial receipt retaining key fields,
a rotated capture and low light. They reported no noticeable slowdown or receipt OCR errors.
The rotated scenario exposed a separate UX defect: the screen rotates while framing remains
portrait. [Issue #242](https://github.com/RizzoG99/PersonalFinanceTracker/issues/242) was created
in iOS Native; it is separate from PERF-301/#241 and is not fixed by this measurement work.

The explicitly selected saved **run 3** of the existing ignored
`traces/Activity-search-5k-PFT-TEST-iPhone-r1.trace` is physical **iPhone 14 Pro Max**, iOS
**27.0.1 (24A446)**, **2026-10-16 12:42:35.210 +02:00**, **256.266551 seconds**, PID 30528,
Nominal thermal state throughout. App signposts verify subsystem
`rizzoG99.PersonalFinanceTraker.test` and binary UUID `DA03F06F-2D8F-368C-884F-6FD7F3F6AE8C`.
Release-TEST was the instructed configuration; the trace does not independently embed the
configuration name or exact Git revision/dirty-source identity. Analysis checkout remains
`3402878` plus the preserved baseline WIP. Runs 1 and 2 were not substituted or merged.

[Redacted run-3 measurements](PERF-301-device-r3.json) retain interval boundaries, executing
threads, per-window CPU attribution and extraction hashes. Raw exports remain under ignored
`.build/perf301/run3-*.xml`. The standard analyzer's `os-log` export contains **zero rows**,
so its initial PFT-event result is incomplete, not evidence that instrumentation was disabled.
Receipt markers are present in **os-signpost**, **PointsOfInterestEvents** and
**OSSignpostIntervals**. Raw receipt rows are duplicated by export: 72 rows reduce to 36 unique
rows by name/type/time/signpost ID/subsystem, cross-checked against the derived interval table.
Only **one capture has retained complete boundaries**, at app event count **5**; do not claim
a five-capture distribution or assign its lighting/framing from that counter alone.

Reproduce the raw signpost extraction with Instruments CLI (read-only export):

```sh
rtk proxy xcrun xctrace export --input .performance-audit/measurements/traces/Activity-search-5k-PFT-TEST-iPhone-r1.trace --xpath '/trace-toc/run[@number="3"]/data/table[@schema="os-signpost"]' --output .build/perf301/run3-os-signpost.xml
rtk proxy xcrun xctrace export --input .performance-audit/measurements/traces/Activity-search-5k-PFT-TEST-iPhone-r1.trace --xpath '/trace-toc/run[@number="3"]/data/table[@schema="OSSignpostIntervals"]' --output .build/perf301/run3-OSSignpostIntervals.xml
```

Resolve XML `id`/`ref` links; pair Begin/End by signpost ID and name within the verified process,
check the opaque request ID, and use end-message `sync_wall_ns`/`thread_cpu_ns` for synchronous
metrics. The standard analyzer still supplies run provenance and Time Profiler attribution;
it currently reads PFT marker messages from `os-log` only. Its missing-marker result must not
be used to discard the native signpost evidence in this run. No analyzer/app code was changed
for this analysis; no new app test run is claimed.

The complete marker window is **197.814684–199.275384 seconds**. Input is **4032×3024** pixels,
orientation raw value 3; crop output is **1450×2917**, upright; Vision input is **994×2000**
with bytes-per-row 7968. Measured stages for this one capture:

| Stage | Wall, ms | Synchronous thread CPU, ms | Actual thread |
| --- | ---: | ---: | --- |
| Camera dispatch to delegate entry | 550.22 | not a synchronous CPU scope | Main at endpoints; includes AVFoundation wait |
| File data representation | 0.62 | 0.60 | Main |
| UIImage construction | 2.58 | 1.61 | Main |
| Orientation | 170.22 | 155.53 | Main |
| Crop render | 58.57 | 51.37 | Main |
| Crop total, including both above | **228.87** | **206.98** | Main |
| Stop request, not awaited teardown | 0.13 | 0.07 | Main |
| OCR preparation | 55.82 | 53.06 | Background |
| Plain Vision interval | 303.88 | not measured as thread CPU | Async, off-main endpoints |
| Enhancement | 35.18 | 10.28 | Background |
| Enhanced Vision interval | 257.64 | not measured as thread CPU | Async, off-main endpoints |

Synchronous rows use the inner `sync_wall_ns`/`thread_cpu_ns` counters. Async/wait rows use
signpost timestamps. Nested crop stages are not added to `crop.total`. Time Profiler independently
has **208 ms sampled main weight** in the crop-total window, including 156 ms in the orientation
window and 52 ms in the crop-render window. These sampled weights agree with the attribution
but are not freeze duration. The nearest app frame in orientation carries 153 ms under
`UIImage.renderUprightPixels`; its total is inclusive framework/image-decoding work, not method
self time. No unrelated global refresh optimization is inferred from the whole-recording CPU.

This was a **fixture acquisition session**: original-photo and quad exports were enabled and
completed on main, **15.06 + 2.26 ms** of additional signpost wall time. Shutter request to
*dismissal request* is **803.14 ms**, including camera wait and exports. It is not a presented-frame
latency or an export-disabled responsiveness baseline. The complete OCR interval after input is
652.61 ms; 33 ms of simultaneous sampled main/UI work must not be labeled OCR CPU.

**Decision:** a >100 ms synchronous image cost is now measured for one real capture. The agreed
conjunction of repeated visible delay and measured image cost is **not met**: the user reports
no noticeable delay and satisfactory OCR in the exercised scenarios. No processing optimization,
executor move, resolution change or OCR-pass change is proposed from this recording. This is
an acceptance observation, not proof of low CPU or automated recognition parity.

There are no Allocations/VM Tracker tables in run 3, so peak resident/physical memory cannot be
reported. At the run-3 checkpoint, the next requested measure was one separate **export-disabled memory
recording**, with three near-full receipt captures. The run-4 section below records what was
actually saved, including its export-enabled configuration and sampling limits. This is not
a latency comparison.
The TEST container and human labels were subsequently recovered for the real-photo correctness
replay below. Do not ask for another broad timing trace solely to collect all five
scenarios when responsiveness is accepted; reassess only if memory pressure or a visible stall
changes the decision.

## Physical iPhone memory follow-up — saved run 4, 2026-10-16

The user saved the next recording in the same trace document as **run 4**. It is explicitly
verified as iPhone 14 Pro Max / iOS 27.0.1 (24A446), **13:02:29.555 +02:00**, **63.399504 seconds**,
PID 30811, Nominal thermal state. The saved template's target `localExecutablePath` identifies
**Release-TEST-iphoneos**, and signposts identify PFT TEST with the same binary UUID as run 3.
Git revision/dirty source identity is still not encoded in the recorded app. The recording
ended with **User pressed Stop**, not a recorded crash. No memory-pressure conclusion follows
from that termination reason.

[Redacted run-4 data](PERF-301-device-r4.json) retain three complete capture paths and 17 VM
snapshots. The native template's instruments-by-run metadata verifies **VM Tracker was added
for run 4**; Allocations was not recorded. The CLI table inventory alone does not expose this
legacy VM data. It is stored in
`instrument_data/2991E8D9-0521-489A-899D-82DE82973FA8/run_data/4.run.zip`, not in an exportable
VM XML table. Never treat absent XML schema names as proof that this native archive is absent.

The saved launch arguments and **six completed fixture-export intervals** confirm
`-performanceAuditReceiptFixtures` was still active. This is a usable observation of the
whole export-enabled receipt flow, not the requested clean export-disabled memory baseline.
The scenario name `PERF-301-device-memory` does not by itself establish instrument settings.

| Capture | Crop wall, ms | Crop main-thread CPU, ms | Main sampled weight in crop window, ms | OCR input pixels |
| --- | ---: | ---: | ---: | --- |
| 1 | 251.86 | 215.85 | 216 | 1244×2000 |
| 2 | 222.24 | 202.20 | 201 | 1222×2000 |
| 3 | 233.76 | 213.51 | 217 | 1084×2000 |

All sources are 4032×3024. Preparation runs off-main at 75.12, 71.36 and 56.35 ms wall.
These are fresh photographed inputs with differing crop geometry and VM Tracker enabled;
do not interpret their differences from run 3 as a before/after improvement or regression.

### Native VM counters and sampling limits

`scripts/perf301_vmtracker_extract.swift` is an **offline macOS analysis helper outside the
app target**. It loads Xcode 27's DVTInstrumentsFoundation/MemoryPlugin archive decoder,
reads the saved legacy NSArchiver stream and obtains counters through XRVMState getters.
It neither records nor launches the app. This uses private Xcode analysis APIs, not app APIs;
other Xcode archive formats may require adapting the helper. No new app dependency, executor
or Sendable workaround is introduced. The dependency-free native extraction supersedes an
exploratory local parser attempt; temporary tools and decoded region data remain ignored.

Native getters yielded 17 snapshots, **3.44–4.08 seconds apart** (median **3.83 s**), using the
recorded device Mach timebase **125/3**. Public snapshot timing is elapsed from the first VM
snapshot; no exact sub-frame alignment is inferred from coarse wall-clock anchors.

| VM Tracker aggregate | Highest observed | Final sample |
| --- | ---: | ---: |
| Resident size | **776.59 MiB** | 746.73 MiB |
| Dirty size | **352.56 MiB** | 303.55 MiB |

Resident size includes mapped/shared clean pages; dirty size is a separate VM-region counter.
Neither is the process's **physical footprint**, which was not recorded here. Virtual address
size is retained only as labeled raw metadata and must not be presented as RAM consumption.
These numbers are **sampled maxima/lower bounds on transient peaks**, not the exact peak inside
a 222–252 ms crop. No per-allocation ownership/lifetime or leak evidence exists without Allocations.

After the earlier captures, dirty samples plateau around **214–216 MiB**. The final three
samples are **352.56 → 318.52 → 303.55 MiB**: they are declining, but the final sample is still
above that earlier plateau. Thus full settling has **not** been established, and three captures
plus this short tail cannot distinguish bounded caches/framework warmup from retained work or
prove a leak. No app-owned memory root cause or pressure/jet-sam threshold is asserted.

**Decision:** retain these bounded measurements and stop processing optimization for the
accepted interaction. The cost on main is now repeated and measured, but the agreed visible-delay
part of the gate remains absent from the user's report. The sampled memory data do not establish
a separate memory-pressure cause. Do not introduce an executor/downscale/lifecycle/OCR-policy
change from this run. No additional broad recording is requested merely to obtain a cleaner
number. Reopen a targeted memory investigation if repeated use shows sustained growth that does
not settle, a memory warning/termination, or a new visible stall; identify the owning allocation
before proposing a change.

The user subsequently supplied the exported TEST container under ignored
`.build/perf301/device-fixtures/`. The eight-photo correctness replay below replaces the former
missing-fixture gate. Its failures do not establish a performance cause or authorize an OCR fix.

### Reproduce and validate the memory extraction

Extract `4.run` from the VM Tracker zip into `.build/perf301/run4-vmtracker.archive` without
changing the saved trace. From the checkout with Xcode 27 installed:

```sh
rtk proxy env DYLD_FRAMEWORK_PATH=/Applications/Xcode.app/Contents/SharedFrameworks:/Applications/Xcode.app/Contents/Applications/Instruments.app/Contents/Frameworks swift -module-cache-path .build/perf301/swift-cache scripts/perf301_vmtracker_extract.swift .build/perf301/run4-vmtracker.archive .build/perf301/run4-vmstates.json
```

The helper executed successfully against this real archive: **17 states**, exact resident/dirty/
swap/virtual-size/region-count parity with the initial native extraction. Mach timebase and
instrument/configuration/argument facts were independently read from the saved `form.template`.
Three complete capture requests and 39 completed receipt intervals were checked from native
signposts, with sampled CPU cross-checks in each crop window. Raw archive/JSON remain ignored;
only content-free counters, limits and source hashes are retained in the report JSON.
No application source changed and no new app build/test run was needed or claimed for this
analysis-only follow-up. Existing receipt correctness/build validation above remains historical.

## Actual path and measurement boundaries

1. The view records `Receipt.shutter.request` **before** launching its existing task.
   A task-local opaque request ID follows this task and the existing caller's OCR task;
   the AVFoundation delegate restores the ID explicitly on its callback thread.
2. `Receipt.camera.wait` starts immediately before capture dispatch and ends at entry to
   `didFinishProcessingPhoto`. It includes AVFoundation work/queueing, not just sensor exposure.
   `Receipt.photo.data` measures `fileDataRepresentation`; `Receipt.photo.construct` measures
   `UIImage(data:)`. Construction can be lazy: later drawing may pay pixel decoding costs.
3. `Receipt.camera.resumed` records the actual MainActor continuation. It reads the current
   normalized quad **after** suspension, matching the existing behavior. A nil quad returns
   the original image without normalization or crop. It does not snapshot a different quad
   at shutter time. Fixture export preserves the exact already-padded quad used.
4. `Receipt.crop.total` encloses the existing synchronous crop. `Receipt.orientation` bakes
   UIImage orientation into scale-1 pixels when needed; an upright image takes its fast path.
   Vision coordinates use `x * width, (1 - y) * height`. The bounding box is intersected with
   the frame; a box <=15% in either dimension falls back to the original image. Otherwise
   `Receipt.crop.render` draws at scale 1 and masks outside the polygon white. No perspective
   correction and no second padding are introduced; the outline already uses factor 1.15.
5. `Receipt.camera.stopRequest` measures only the synchronous call to the existing stop method;
   queued session teardown is not awaited. `Receipt.camera.finish` precedes the callback.
   Both actual callers record `Receipt.dismiss.request` before setting the cover binding false.
   These markers are **requests**, not proof of cover disappearance or a presented frame.
6. The caller starts its existing OCR task. `Receipt.ocr.input` records pixels/orientation;
   `Receipt.ocr.prepare` retains the existing scale-1 upright/downscale to a longest side of
   2000 pixels, with no upscaling. `Receipt.ocr.prepared` records the actual Vision input size.
   `Receipt.ocr.plain`, `Receipt.ocr.enhance` and `Receipt.ocr.enhanced` retain both passes
   and the existing mean-confidence choice. Async Vision intervals are wall time including
   suspension; only synchronous scopes report executing-thread CPU.

The pre-finish crop/orientation can delay requesting dismissal. OCR preparation can overlap
an already-requested dismissal, depending on actual scheduling and its executing thread.
Camera wait, actor queueing, stop-request work, OCR and presentation must remain distinct.
**MainActor source isolation is not proof of a visible stall.** Nested `crop.total` includes
orientation and crop rendering; do not add all three durations together.

Instrumentation is opt-in (`-performanceAudit` or `PFT_PERFORMANCE_AUDIT=1`), uses existing
signposts with unique interval IDs, records request ID/thread/pixel dimensions only, and adds
no financial contents or image fingerprints to public device logs. Existing DEBUG receipt
logs/result bundles can contain private data and must remain local.

## Repeatable fixtures and automated checks

`ReceiptImageProcessingTests` exercises the real crop/preparation helpers: eight orientations
including mirrored inputs; bottom-origin coordinates; single padding and clamping; white
polygon mask; absent/empty/tiny-quad fallback; frame intersection; 2000px cap and no upscaling.
The orientation oracle is UIKit's displayed image, separate from the crop implementation.
Degenerate cases cover the existing fallback, not a new general validator for arbitrary
self-intersecting/non-finite polygons. The production segmentation still supplies four corners.

`ReceiptImageBaselineTests` generates an immutable, non-sensitive 4032×3024 synthetic receipt
and re-decodes fixed JPEG bytes. Eight cases cover no quad, near-full frame, partial receipt,
diamond mask, tiny invalid quad and an already-padded quad, with upright/right/left/down inputs.
Fixture construction is outside timed intervals. Round 0 is first pipeline use for that case
(not process-cold UIKit); round -1 is an instrumentation-disabled pixel-parity control;
rounds 1...5 are warm repeats. Each iteration uses an autorelease pool. All transforms in
this harness intentionally run on MainActor; it does **not** establish the actual recognizer
thread or camera latency. `ReceiptRecognitionBoundaryTests` separately calls the real async
recognizer and records its actual synchronous thread samples and two Vision boundaries.

The harness records process-lifetime `getrusage.ru_maxrss` (Darwin bytes) before/after each
iteration. It includes fixture/runtime/test overhead and prior iterations. It is **not** a
per-stage peak, device resident-memory delta or estimate of jetsam risk. Device memory needs
the dedicated recording below. Pixel hashing happens after the measured stage/memory sample.

### Results

Optimized transform run: **1 test passed, zero failures/skips**, with all **56 records**.
The JSON and result bundle confirm the test executed. Device: iPhone 17 Simulator,
iOS 27.0 (24A434), `pft-performance-baselines`, UDID
`F160101A-8C10-4335-A155-D4156F027578`, en_US / Europe/Rome.
Local result: `.build/perf301/baseline-release.xcresult`; source attachment hash and all
stage medians/ranges are in [the redacted summary](PERF-301-simulator-summary.json).

| Synthetic 12MP case | Crop wall median (range), ms | Crop thread CPU median, ms | OCR preparation wall median, ms |
| --- | ---: | ---: | ---: |
| Upright, full quad | 44.73 (43.80–49.02) | 44.39 | 31.76 |
| Right orientation, full quad | 83.82 (79.68–86.88) | 83.52 | 32.79 |
| Left orientation, partial quad | 66.56 (65.32–67.97) | 66.33 | 16.61 |
| Down orientation, diamond | 79.02 (73.52–80.64) | 78.58 | 30.77 |
| Right orientation, tiny invalid quad | 55.21 (54.82–55.42) | 55.08 | 34.29 |
| Upright, already-padded quad | 38.54 (38.24–38.91) | 38.40 | 18.28 |
| Upright, no quad | skipped | skipped | 28.07 |
| Right orientation, no quad | skipped | skipped | 58.60 |

Five warm observations per row; full per-stage first-use and variance are retained in JSON.
For the upright/no-quad case, first preparation is 68.32 ms versus the warm 27.39–28.79 ms
range. Do not treat a first instrumented operation as an app cold-launch benchmark.
The invalid quad still pays orientation before its existing box-size fallback and then
returns the original; that is a measured harness path, not authorization to optimize it.
All eight cases retain identical crop/preparation pixel signatures for the disabled
control and six instrumented rounds. No nested intervals are summed in the table.

The maximum cumulative test-host watermark is **763.17 MiB**. It includes fixture generation,
image hashing/runtime and earlier iterations and cannot identify a camera-stage memory peak
or device pressure. No physical-memory conclusion or change is justified by that number.

The separate real async recognizer smoke test passed **1 test**, zero failures/skips:
preparation actually executed **off the main thread**, 17.03 ms wall / 13.54 ms thread CPU;
enhancement also executed off-main, 465.49 ms wall / 37.69 ms thread CPU. The first plain and
second Vision intervals were 2852.37 and 758.13 ms wall. This is **one first-use synthetic
2400×1600 Simulator input**, not a distribution, equivalent 12MP preparation comparison,
OCR quality benchmark, device result, or reason to change dual-pass OCR. It demonstrates why
the async recognizer thread must be measured rather than inferred from its MainActor caller.
Local result: `.build/perf301/recognizer-release.xcresult`; content-free samples retained in JSON.

Physical stage timing and coarse VM observations are recorded above. Visible-frame latency and
exact transient peak remain unmeasured. The historical named private receipt corpus is still
absent; its end-to-end test skip must not be reported as accuracy validation. The newly supplied
UUID corpus is independently exercised below.

### Exported iPhone photo replay — correctness baseline

The user supplied `rizzoG99.PersonalFinanceTraker.test/Documents/PERF301Fixtures` inside the
ignored downloaded container. It contains **eight byte-preserved JPEG originals** (exported
with `.receiptphoto` extension) and matching JSON quadrilaterals. All are 4032×3024, UIImage
orientation raw value 3, with four already-padded finite corners. They depict **one receipt**
with varied scale, framing, physical rotation and illumination. These are eight input images,
not eight distinct receipts or eight retained physical timing samples. All real quads are
present/valid; absent/invalid and mirrored cases remain covered by the synthetic geometry suite.

Expectations were read visually from local previews before OCR output was inspected. Originals,
previews, financial/merchant/date labels, OCR text and result bundles remain ignored locally.
Only opaque IDs, SHA-256 source hashes and boolean comparison results are published in
[the redacted fixture result](PERF-301-device-fixtures.json). The initial `sips` preview conversion
produced black output; Pillow EXIF-transposed previews exposed the valid original pixels. No
converted preview was used as OCR input or substituted for an exported original.

`ReceiptImageDeviceFixtureTests` runs the actual camera crop and actual dual-pass recognizer,
then the existing parser with fixed reference date 2026-10-16. Release-TEST / ENABLE_TESTABILITY,
en_US, Europe/Rome; iPhone 17 Simulator / iOS 27.0 (24A434). The first `scripts/xcb` execution
ran **one failing test function, zero skips**, **all eight replays**, with nine JSON attachments
(eight results and a completed-count record). Resources were confirmed bundled. Results:

- Total matches the printed expectation on **7/8** inputs. On one input the parser result is
  the printed tax amount; the correct total is also present in the recognized text.
- Date matches on **8/8**, without clamping.
- Merchant matches exactly on **3/8**. Four differences lose only the printed accent; one
  rotated view selects a damaged table-heading word instead of the merchant.
- The test tree contains **six failed assertions**: one total and five merchant comparisons.
  The xcb summary shows only a representative failure; it is not the full failure inventory.
  All image orientation/dimension/quad and completed-interval assertions passed.

This **red baseline is preserved**, not normalized into a passing result. The user's report of
acceptable device OCR remains a separate observation: Simulator Vision/OS and replay results
cannot retroactively prove which fields the physical app presented. No image-processing
optimization or OCR/parser-policy fix has been applied. Before a future optimization, compare
the exact original/quad corpus and account for these existing correctness failures separately.
Initial raw result: `.build/perf301/device-fixture-parity.xcresult`.

A second isolated run retained **identical total/date/merchant results on all eight inputs**:
one failed function, zero skips, the same six assertion failures. It saved eight crop previews
and six diagnostic uncropped controls (the inputs with any failing field). The problematic
total and rotated-merchant crops were inspected visually: their expected fields remain visible.
The recognizer's crop output contains the correct total before its label, consistent with a
layout/order-sensitive extraction problem; the precise Vision/table/parser branch is not yet
isolated. This does not demonstrate a crop-coordinate loss or a safe performance shortcut.
On the six selected originals without crop, only two totals match and four are absent, including
the problematic-total input. These controls change the recognizer's input scale/layout and are
diagnostic only, not equivalent performance comparisons or a proposed bypass. Stop the diagnosis
at this recorded baseline; any OCR/parser correction is separate work. Second raw result:
`.build/perf301/device-fixture-diagnostics.xcresult`, with **23 attachments**: eight result JSON,
eight crop JPEGs, six original-control JSON and one eight-replay completion record.

## User-operated iPhone / PFT TEST protocol

### A. Acquire local fixtures (separate from timing)

1. Select `PersonalFinanceTraker-TEST`; ProfileAction is **Release-TEST**, confirmed in the
   preserved local scheme. Verify the app is **PFT TEST**, not the production identity.
   Keep the current store; do not enable seeding. Record phone model/OS, build identifier,
   commit plus dirty source hashes, language/timezone and thermal state. Unlock manually
   if Release ignores debug-only bypass flags.
2. For this fixture acquisition only, add launch arguments:
   `-performanceAudit -performanceAuditScenario PERF-301-fixtures -performanceAuditReceiptFixtures`.
3. In Activity, tap Add, wait until the form settles, then Scan Receipt → Take Photo.
   Capture full and partial receipts (keep the total/date/merchant to be asserted visible),
   upright and rotated shots, and a dim shot; include a near-full high-resolution frame,
   a small receipt in a wider frame, and one capture without a detected outline if possible.
   Synthetic tests supply deterministic invalid quads; do not depend on unstable detection
   to reproduce a particular invalid quad on hardware.
4. The opt-in export saves original AVFoundation bytes as `<request>.receiptphoto` and the
   exact used quad/orientation/pixel metadata as `<request>.json` under the TEST app's
   `Documents/PERF301Fixtures`. It neither recompresses nor strips EXIF. Download the TEST app
   container with Xcode Devices and Simulators; keep it under `.build/perf301/device-fixtures/`.
   Originals contain personal data. Export-failed markers mean the pair is incomplete.
5. Copy selected pairs into ignored
   `PersonalFinanceTraker/PersonalFinanceTrakerTests/Fixture/Receipts/`. Add local
   `perf301-expectations.json`, an array such as:
   `[{"id":"<request>","total":"12.34","date":[2026,10,16],"merchant":"Expected merchant"}]`.
   Set date/merchant null only when they cannot be established; total is required. Labels
   must come from reading the receipt, not from accepting OCR output. The test's reference
   date is fixed at 2026-10-16. Keep all these files local, verify `git check-ignore`, then
   rebuild the test target so Xcode copies resources. The opt-in device-fixture test fails
   for missing resources rather than silently treating them as accuracy evidence.
6. Remove `-performanceAuditReceiptFixtures` before any latency/memory run. Its explicit
   `Receipt.fixture.export` disk I/O makes acquisition runs incomparable with baseline runs.

### B. Capture latency and memory

The user controls the phone and Instruments; no recording/launch delegation is assumed.
Use the same intended iPhone (previous evidence used an iPhone 14 Pro Max; record the actual
selected device), optimized TEST binary/symbols, store, language, thermal state and audit flags
for all comparable runs. Arguments:
`-performanceAudit -performanceAuditScenario PERF-301-device-baseline`.
Disable fixture export. Do not compare a Debug Simulator run with this device run.

1. Record **Time Profiler + Points of Interest** targeting PFT TEST. Wait five seconds after
   launch/unlock. Enter Activity → Add → Scan Receipt → Take Photo; wait for a stable outline,
   shoot and wait for Reading receipt to finish. Record the first scan separately.
2. Repeat five warm scans for a near-full receipt, then five for a partial receipt retaining
   the key fields, using the same lighting, distance/orientation and camera settings. Leave
   five seconds between scans. Separate rotated/no-outline scenarios into named runs when
   available. Note whether the visible delay occurs before closing the camera, during the
   transition, or behind the OCR progress indicator, and whether it disrupts use.
3. Wait five seconds after the final result; stop and **save** under
   `.build/perf301/traces/PERF-301-device-latency.trace`. Record the selected run number and
   action order. No Hitches instrument is assumed available. A finish/onDisappear marker
   alone does not establish frame latency; retain the user's observation separately.
4. In a separate run, use **Allocations + VM Tracker**, with Points of Interest where supported,
   for the same actions. Record resident/physical footprint before the shutter, highest observed
   value over callback→crop→OCR preparation, and after OCR settles; distinguish live/allocated
   bytes from resident footprint. Save `.build/perf301/traces/PERF-301-device-memory.trace` with
   run number. Record memory warnings/termination if any. Do not infer a physical memory peak
   from the Simulator test-host watermark or sample only the endpoints of a transient allocation.
5. Return saved trace paths/run numbers, device/build metadata and the visible-delay observation.
   Do not send personal image contents in GitHub comments. Analyze the saved artifact before
   requesting another recording; a missing table is missing evidence, not zero cost.

Inspect/extract the saved run without controlling the device:

```sh
rtk python3 .agents/skills/performance-profiling/scripts/analyze_trace.py inspect .build/perf301/traces/PERF-301-device-latency.trace
rtk python3 .agents/skills/performance-profiling/scripts/analyze_trace.py analyze .build/perf301/traces/PERF-301-device-latency.trace --run 1 --marker Receipt.shutter.request --occurrence 1 --pre 0.5 --duration 5
```

Select the **actual** run/occurrence after inspection; expand the window if the result lies
outside five seconds. Correlate opaque request IDs with callback/resume/crop/prepare/OCR,
retain pre-marker work and distinguish sampled CPU weights from wall duration. Use Instruments'
resident-memory timeline for the separate memory run; the existing analyzer does not derive
peak footprint from allocation counts.

## Stop criterion and remaining limits

The agreed materiality gate is **repeated visible delay plus >=100 ms of attributed synchronous
main-thread image work** in a physical-device interaction window. Assess actual memory pressure
separately. A slower camera wait, background OCR, Simulator duration or cumulative watermark
alone does not satisfy that gate. No physical symptom/root cause has yet been proved.

If the gate is met, rank falsifiable causes from the observed stage/thread stacks, choose one
bounded change, preserve orientation/quad/visible content/2000px input/real OCR expectations,
and repeat the same measurement. Replay the exact saved original/quad corpus to compare
geometry/OCR outputs; live camera photographs vary and cannot establish pixel identity across
runs. Match build/instrumentation, scene, settings, thermal state and first/warm status for
physical timing comparisons. Do not add unsafe UIImage Sendable wrappers. If the gate is
not met and everyday use is acceptable, document and stop. If the follow-up has no clear gain,
stop structural changes. Camera lifecycle and dual-pass OCR remain separate scopes unless the
recording changes the diagnosis. No reopening accepted analytics/search work.

Current stop: **no processing optimization after accepted device use and the bounded run-4
memory observation. The supplied photo/quad corpus now has a recorded red correctness baseline;
keep OCR/parser correctness separate. Reconsider performance code only for a new visible stall
or demonstrated sustained memory pressure.**
Light/dark appearance, compact/wide UI, Dynamic Type and VoiceOver checks and
user-visible frame measurements have not been run in this follow-up. The user has now exercised
the real camera and reported satisfactory responsiveness/OCR plus the rotation defect #242.
Existing controls, semantics
and presentation are unchanged; source review is not visual validation. No physical memory,
energy, jetsam, passing real-photo accuracy or before/after speedup result is claimed.

## Automated reproduction and validation

Final-review maintenance: the async recognizer counter harness is now explicitly opt-in
(`PFT_RECEIPT_RECOGNITION_BASELINE=1`) and TEST-only. It changes process-wide recorder state
across awaits and must run alone; ordinary integration runs report an explicit skip.
Earlier executed measurements/source hashes below retain their historical provenance.

Run from this worktree, serially. Preserve result bundles before the next `scripts/xcb test`,
which replaces `.build/Test.xcresult`. The recorder and isolated baseline tests run alone
because their settings are process-wide. Raw bundles/attachments stay under ignored `.build/perf301/`.

```sh
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST TEST_RUNNER_PFT_RECEIPT_BASELINE=1 scripts/xcb test -configuration Release-TEST ENABLE_TESTABILITY=YES -only-testing:PersonalFinanceTrakerTests/ReceiptImageBaselineTests -collect-test-diagnostics never -testLanguage en -testRegion US
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST TEST_RUNNER_PFT_RECEIPT_RECOGNITION_BASELINE=1 scripts/xcb test -configuration Release-TEST ENABLE_TESTABILITY=YES -only-testing:PersonalFinanceTrakerTests/ReceiptRecognitionBoundaryTests -collect-test-diagnostics never -testLanguage en -testRegion US
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST scripts/xcb test -only-testing:PersonalFinanceTrakerTests/PerformanceAuditRecorderTests -collect-test-diagnostics never -testLanguage en -testRegion US
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST scripts/xcb test -only-testing:PersonalFinanceTrakerTests/ReceiptImageProcessingTests -only-testing:PersonalFinanceTrakerTests/ReceiptParserTests -only-testing:PersonalFinanceTrakerTests/ReceiptForeignCorpusTests -only-testing:PersonalFinanceTrakerTests/ReceiptEndToEndTests -only-testing:PersonalFinanceTrakerTests/ReceiptImageDeviceFixtureTests -only-testing:PersonalFinanceTrakerTests/EditAddTransactionViewModelTests -collect-test-diagnostics never -testLanguage en -testRegion US
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST scripts/xcb test -only-testing:PersonalFinanceTrakerTests/ReceiptCategoryPairingTests -collect-test-diagnostics never -testLanguage en -testRegion US
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST TEST_RUNNER_PFT_RECEIPT_FIXTURES=1 scripts/xcb test -configuration Release-TEST ENABLE_TESTABILITY=YES -only-testing:PersonalFinanceTrakerTests/ReceiptImageDeviceFixtureTests -collect-test-diagnostics never -testLanguage en -testRegion US
```

The last command now ran with the local acquired images/labels and is **red**, as documented above.
The existing `ReceiptEndToEndTests` also needs its original named corpus, not the new UUID
fixture set. Keep its skip explicit if those originals remain unavailable.

Export and summarize the synthetic attachments (substitute the exported filenames):

```sh
rtk proxy xcrun xcresulttool export attachments --path .build/perf301/baseline-release.xcresult --output-path .build/perf301/baseline-attachments
rtk proxy xcrun xcresulttool export attachments --path .build/perf301/recognizer-release.xcresult --output-path .build/perf301/recognizer-attachments
rtk python3 scripts/perf301_receipt_summary.py .build/perf301/baseline-attachments/9C467F31-0424-4732-BD2F-FAAE1A939677.json --recognizer .build/perf301/recognizer-attachments/DB989653-53FA-4A11-A5FC-132252408425.json --output .performance-audit/measurements/PERF-301-simulator-summary.json
```

The summarizer validates round coverage, stage/thread coverage, dimensions, disabled control
and pixel parity. Four deliberate corruptions (missing record, pixel mismatch, wrong thread,
duplicate round) were rejected; the original 56 records were accepted.

Validated so far:

- Geometry: 6 passing test functions / 17 executions, zero failures/skips.
- Release-TEST synthetic transform baseline: 1 passing test, zero failures/skips; 56 records.
- Release-TEST actual async recognizer boundary test: 1 passing test, zero failures/skips.
- Recorder: 4 passing tests, zero failures/skips, run separately.
- Actual `ReceiptCategoryPairingTests`: 17 passing tests, zero failures/skips, confirmed in the xcresult. Local result `.build/perf301/category-regressions.xcresult`.
- `scripts/xcb build -configuration Release-TEST` with the TEST scheme passed (Simulator destination). Existing camera lifecycle Sendable/session-isolation warnings remain outside scope; no unchecked conformance was added or warnings suppressed.
- Final receipt/form/geometry regression: 117 passing test functions / 128 passing executions,
  zero failures, 3 explicit skipped functions: missing original receipt photos, missing foreign
  corpus, and the opt-in new device-fixture test. All intended suites appear in the xcresult
  test tree. Local result `.build/perf301/receipt-regressions.xcresult`.
- Subsequent supplied-photo replay: one opt-in function executed twice, **failed both times**,
  zero skips, all eight photos processed each time, six assertions per run. This supersedes the
  missing-new-fixture skip for local coverage; the two historical private corpora remain absent.
  Earlier passing totals are unchanged; these two red executions are not counted as passes.

A first optimized harness compile attempt ran **zero tests** due to a Swift Testing macro
expansion on an `allSatisfy` key path; it was corrected to a closure and excluded. The initial
regression command's `ReceiptCategoryInferrerTests` filter matched no suite; the actual suite
is `ReceiptCategoryPairingTests`, so category coverage is validated separately, not inferred
from that first command's successful exit. No performance-regression reproduction is claimed
from either harness setup error.

### Source identity

These hashes identify the measurement contribution on top of initial HEAD and preserved WIP;
the trace must still establish its own binary/device provenance.

- `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/Components/ReceiptCameraView.swift`: `354dc71bb4bb3fd2e869b6e9e5f42dd7a40c3ac1f0134715a47f77510b83c027`
- `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionView.swift`: `0d1db2ccd34ea9d40bac89ed96cff1b6a7ac02500e72892b953f60d5997c4992`
- `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/ReceiptScanShortcut.swift`: `ca59314e6e455fb8c406645bf9a27de20500a25c3df36e4327925b0299f0e3db`
- `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/ReceiptTextRecognizer.swift`: `4b7a5c7540224e11db4009c1f99b3c5eedae7b693ca3406126631ab263b17375`
- `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/PerformanceAuditRecorder.swift`: `bcdfcbb11cab9eebb25952ea519f5b4e9e4088d76bd6acc68d624859168397b2`
- `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/ReceiptImageAudit.swift`: `0cd3bd421a4203fec990bd9fccd62d1a06275c0d475735e26187f542edbe1e42`
- `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/ReceiptImageProcessingTests.swift`: `9464c86691971635d3c71510279561e1249b5eb20c912b4662f0757c9e591c56`
- `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/ReceiptImageBaselineTests.swift`: `1d21459b99b206754294a903446c9f5d3218d7f6b8b7c5c7e6856b9d535dfb6b`
- `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/ReceiptRecognitionBoundaryTests.swift`: `899a3655a78066e34d918cc6216f18aa025c24a414b55b91e47ad58b17e950bc`
- `scripts/perf301_receipt_summary.py`: `7cc64f7c88143c6ebc6a90336451f4c3e24443a2ae16aadb6164c993333238bd`

### Preservation and final checks

40 of the original 43 WIP files remain byte-identical. Only the existing summary, manifest
and roadmap received the scoped reconciliation/additions described above; local original
copies and fingerprints are retained under `.build/perf301/`. The changelog, project/TEST
configuration, scripts/xcb, widgets, data seeder and unrelated reports were not changed.
`git diff --check` passed. Raw fixture/trace paths were verified ignored. `graphify update .`
completed and left Git status unchanged. The issue remains In Progress, not closed; #235
is still open for review. No commit/push/PR mutation was made in this follow-up.

After local-photo replay, 53/58 files in the pre-fixture WIP snapshot remain byte-identical.
Only this report, summary/manifest/roadmap and the opt-in test harness changed; the new redacted
fixture JSON is the additional report artifact. All eight copied original/metadata pairs were
byte-verified against the exported container; originals, labels, crop previews and both xcresults
are ignored. Final `git diff --check` passed; graphify updated with no topology change or new
tracked files. Production code, project/TEST configuration and unrelated WIP were untouched in
this fixture follow-up. No broad suite rerun was needed for the test-only diagnostic addition.

Native VM extraction helper SHA-256: `d7d862f36d4007480b709b0e555badcc3c16a22b9b6bc8fdca6df2fe1eb54382`.
