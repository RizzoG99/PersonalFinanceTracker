# PERF-301 / #241 — single-pass rendering experiment, rejected

## User acceptance — 2026-10-16

[Recorded in GitHub #241](https://github.com/RizzoG99/PersonalFinanceTracker/issues/241#issuecomment-6218902824).

The user explicitly accepted retaining the current production pipeline and stopping PERF-301
in the verified scope, then requested recording this acceptance in GitHub #241 and the audit.
Disposition remains **BASELINE_MEASURED_STOP_IN_SCOPE**; this is an accepted stop, not a claim
that performance problems are impossible on every supported iPhone.

Verified conditions and limits:

- On the user's iPhone 14 Pro Max / iOS 27.0.1, full, distant, partial, rotated and dim receipt
  captures produced no reported noticeable slowdown or OCR error. Historical runs 3/4 still
  measure material synchronous main-thread crop work (about 222–252 ms wall). These observations
  predate the integrated rotation fix and do not validate its live-camera behavior.
- On the updated `e8df73f` plus preserved WIP, Release-TEST / iPhone 17 Simulator / iOS 27.0,
  the restored pipeline passes 122 regression functions / 148 executions with zero failures or
  skips. All eight local photos of one receipt preserve exact crop/prepared-OCR pixels and,
  in the separate actual OCR replay, full recognized lines and parsed fields versus baseline.
- The strict OCR accuracy replay remains red: six existing assertions, total correct 7/8,
  date 8/8, exact merchant 3/8. Output preservation does not mean perfect recognition. Those
  correctness issues remain separate from this performance acceptance.
- No updated physical-device before/after, older-device coverage, exact transient memory peak,
  physical footprint, energy or frame-latency result is established. Raw photos, financial
  expectations, OCR text and traces remain local and ignored.

The single-pass candidate is **discarded** despite a 22–48% synthetic rotated-crop CPU reduction:
one of eight real images changes crop/OCR-input pixels and recognized lines. Parsed key fields
stay unchanged, so this is a failed preservation gate, not evidence of a newly wrong total.
The exact pre-experiment camera source is restored; no production optimization is retained.

No further optimization is scheduled. Reopen for new evidence of a repeatable visible stall,
sustained growth or memory pressure/termination, or an explicitly authorized, separately bounded
experiment on less powerful hardware. Accepted PERF-201/PERF-112/PERF-111 stops and deferred
PERF-303/#237 remain unchanged. This records acceptance without closing the GitHub issue or
changing project status; retained PR #230 scope remains tests, instrumentation/tooling and reports.

## Decision

**The candidate was implemented, measured and reverted. No production optimization is retained.**
It reduces synthetic rotated-crop CPU, but changes crop and OCR-input pixels on one of eight
real photographs. Key parsed fields stay unchanged; the recognized line list changes on that
photograph. This is a failure of the experiment's preservation gate, not proof of a newly wrong
total. Do not request another generic device recording for this rejected implementation.

This is the one preventive experiment the user authorized after accepting the initial device
interaction, motivated by less powerful supported iPhones. It does not reopen accepted
PERF-201/PERF-112/PERF-111 work or deferred PERF-303/#237. Audit ID **PERF-301** remains GitHub
**#241**. Main's rotation fix #243/#242 remains integrated.

## Provenance and scope

Worktree `.worktrees/performance-baselines`, branch `chore/performance-baselines`, HEAD
`e8df73fada945da6238f3ec9baac7f71ae70c24b` plus preserved WIP; main `cc86f16` is already merged.
The baseline was rerun on this updated source before editing the production renderer.
Pre-experiment camera SHA-256 (also the final restored camera):
`0bce45929ad2c2b3e50c78d61c661b97d5419c5b68ff1eb59fafd593aa7e90e2`.
Full redacted results and candidate/source hashes: [experiment JSON](PERF-301-single-pass-experiment.json).

Release-TEST, `ENABLE_TESTABILITY=YES`, TEST bundle, en_US / Europe/Rome; iPhone 17 Simulator,
iOS 27.0 (24A434), `pft-performance-baselines`, on the same host. Both transform runs execute
the identical existing synthetic harness alone, with 56 records, one passed test, zero skips.
Eight cases each include first use, an instrumentation-disabled control, and five warm repeats.
The added correctness test module was linked for the candidate; no correctness test ran inside
the timed harness. First use is not process-cold camera latency. This is not a device speed result.

The attempted change affected only the camera crop helper: draw the rotated opaque scale-1
UIImage directly into its final crop canvas, avoiding a full-frame upright intermediate.
Scaled/transparent inputs kept the old path. Pixel coordinates, single padding, polygon mask,
white surround and crop/OCR dimensions were preserved. No executor, Sendable workaround,
camera lifecycle, OCR-pass policy, recognition resolution or parser change was introduced.

For PR #230, the retained contribution is the crop regression oracle, phase-aware summary
tooling and redacted reports/status updates. The rejected renderer and diagnostic source remain
local under ignored `.build/perf301/single-pass/`; they are not a production change for that PR.
No changelog bullet is added for a reverted prototype and test/tooling-only retained changes.
No new commit, push, merge or remote PR mutation was made during this experiment.

## Local measurements

Warm medians, five observations per case. All measured synchronous work in this harness is on
main. `crop.total` includes child intervals; do not add nested times. The summary JSON retains
first-use values, ranges, actual thread samples and attachment hashes.

| Case | Before → candidate wall, ms | Before → candidate thread CPU, ms | CPU change |
| --- | ---: | ---: | ---: |
| Right, full quad | 80.40 → 63.59 | 80.16 → 62.62 | −21.9% |
| Left, partial quad | 65.99 → 34.59 | 65.80 → 34.47 | −47.6% |
| Down, diamond mask | 79.01 → 61.27 | 78.74 → 60.45 | −23.2% |
| Right, tiny invalid quad | 57.47 → 0.006 | 57.32 → 0.005 | Avoids discarded orientation work |
| Upright, full quad | 44.45 → 48.32 | 44.27 → 46.94 | +6.0% |
| Upright, padded quad | 39.22 → 40.52 | 39.08 → 40.37 | +3.3% |

Rotated valid-crop CPU falls by 22–48% locally. Upright controls increase by 3–6%; this single
before/after sequence does not establish a stable upright regression or a device latency gain.
The tiny-quad result is an early fallback, not a representative successful receipt crop.
Absent-quad paths remain outside `crop.total`. Synthetic crop/preparation signatures match for
all eight cases across before/candidate runs and within enabled/disabled controls. Synthetic
parity alone was insufficient: the real photograph exposed the sampling change.

Process-lifetime test-host high-water is **753.75 → 725.81 MiB** in the separate processes.
These numbers include fixture generation, hashing and runtime. They are neither per-stage peaks
nor physical footprint; no exact transient-peak reduction, memory-pressure or jetsam conclusion
is drawn. No new physical Instruments recording was taken. Earlier run-3/run-4 device numbers
retain their pre-rotation-fix provenance and are not a comparison with this candidate.

## Correctness feedback loop

The structural test first went red on the unmodified source: one full-frame orientation
interval precedes crop rendering. The frozen two-render test oracle passed its synthetic
orientation/scaled/transparent comparisons before implementation. With the first candidate,
the structural/geometry/orientation tests passed, but the real-photo comparison failed.

All eight originals/quads come from the user's existing private exported TEST container.
The frozen reference's JPEG outputs were checked against all eight actual pre-experiment crop
attachments: **8/8 match**. Thus the real-photo failure is not explained by an invented oracle.
The encoder hashes anchor this same-platform diagnosis; they are not a cross-OS test contract.

One input, opaque ID `60593A10-CFAF-4C61-A369-A7A02925D21B`, fails both crop and prepared-OCR
pixel parity. Crop remains 1546×2246, OCR input 1377×2000. Comparing the lossless crop outputs
finds **1,099,133 / 3,472,316 pixels** different (about 31.7%), maximum RGB channel delta 47/255,
mean absolute channel delta 0.654/255. This spans the image, not just a changed border pixel.
Seven other real inputs match exactly. All source photos remain byte-preserved.

Two bounded probes did not restore parity: translate the graphics context and draw at origin;
then reconstruct a UIImage from the same CGImage/scale/orientation in the test. The exact UIKit/
Core Graphics sampling mechanism remains unisolated. No interpolation tuning, dimension changes,
content cropping or fixture-specific bypass was added to force a passing result.

The actual dual OCR/parser replay also executed on all eight candidate inputs. Total, date and
merchant results remain identical to baseline on **8/8**, including the existing errors (total
correct 7/8, date 8/8, exact merchant 3/8). The strict expected-fields test still fails six
assertions. Recognized line lists match on **7/8** and change on the pixel-mismatch input.
There is no complete human line transcription establishing whether those changes improve or
degrade recognition. Unchanged key fields therefore do not establish full quality preservation.

**Stop:** retain the exact pre-experiment production pipeline. The numerical improvement does
not override the failed input-preservation gate. This rejects this implementation attempt,
not every possible future optimization. Any further approach needs a separately bounded
experiment; do not silently extend this one into downscaling, executors or OCR-policy changes.

## Final validation and retained work

After rollback, the camera file is byte-identical to its saved pre-experiment version.
`ReceiptCropParityTests` retains eight-orientation, odd-dimension, fractional-quad, scale and
transparency comparisons against the frozen oracle. `ReceiptCropFixtureParityTests` retains
the exact real crop and prepared-OCR pixel gate. The temporary structural goal/probe was removed
from the normal test suite because the proposed optimization was rejected; its executed red
evidence and experimental source are retained locally.

Final targeted regression: **122 test functions / 148 executions passed**, zero failures/skips.
All six requested suites appear in the xcresult, including the real-photo test: crop and
prepared-OCR pixels match the original pipeline on **8/8**. The separate strict OCR test has
the documented existing accuracy failures. Its final restored replay processed all eight photos:
total/date/merchant **and full recognized line lists match the pre-experiment baseline on 8/8**;
one failed function, six existing assertions, zero skips. This is not counted as a passing
accuracy test. Its result is recorded separately in the JSON.
The summary tool accepts both explicit pipeline schemas and rejects labeling pre-change stage
records as single-pass. Raw PNG/JPEG/OCR/xcresults stay ignored under `.build/perf301/single-pass/`.
Physical-device speed, peak memory, energy, camera rotation and visual/accessibility UI checks
were not run in this experiment. No changed user-facing view or physical improvement is claimed.

Reproduce final checks with the local ignored receipt resources present:

```sh
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST TEST_RUNNER_PFT_RECEIPT_FIXTURES=1 scripts/xcb test -configuration Release-TEST ENABLE_TESTABILITY=YES -only-testing:PersonalFinanceTrakerTests/ReceiptCropParityTests -only-testing:PersonalFinanceTrakerTests/ReceiptCropFixtureParityTests -only-testing:PersonalFinanceTrakerTests/ReceiptImageProcessingTests -only-testing:PersonalFinanceTrakerTests/ReceiptCameraGeometryTests -only-testing:PersonalFinanceTrakerTests/ReceiptParserTests -only-testing:PersonalFinanceTrakerTests/EditAddTransactionViewModelTests -collect-test-diagnostics never -testLanguage en -testRegion US
rtk python3 scripts/perf301_receipt_summary.py .build/perf301/single-pass/before-records.json --output .build/perf301/single-pass/reproduced-before.json
rtk python3 scripts/perf301_receipt_summary.py .build/perf301/single-pass/candidate-records.json --single-pass --output .build/perf301/single-pass/reproduced-candidate.json
```

The last command summarizes archived **rejected-candidate** data; the restored production code
does not implement that pipeline. Preserve each xcresult before another `scripts/xcb test`.
WIP fingerprints/copies are local in `initial-wip.json` and `before-sources/` under the same
ignored experiment directory. Main checkout WIP and the existing local merge are preserved.
Of the 60 pre-experiment WIP fingerprints, **55 remain byte-identical**, including the camera,
changelog, TEST project/settings, scripts/xcb and all unrelated source. Only four scoped audit
documents and the summary tool changed. Three new scoped artifacts are the crop oracle test,
this report and its JSON. `git diff --check` passes; the index remains empty; graphify updated
without changing Git status. No temporary renderer or source-wrapper probe remains in the app.
