---
name: diagnosing-bugs
description: Diagnose hard or recurring bugs and performance regressions with a red-capable feedback loop. Use when the user asks to diagnose or debug uncertain behavior. Do not use when the cause and requested fix are already established.
license: MIT
metadata:
  upstream_repository: "https://github.com/mattpocock/skills"
  upstream_revision: "6fd947921b935b7e1e69293a200400f0fdd5c15f"
  upstream_path: "skills/engineering/diagnosing-bugs"
---

# Diagnosing Bugs

Prove the symptom, root cause, and fix. Follow the repository's `AGENTS.md`, including its Graphify, worktree, build, test, SwiftUI, localization, and evidence rules. Read relevant ADRs, feature docs, and handoffs when they exist.

## Redact

This skill has you show commands, outputs and captured artifacts. **Redact every secret first**: write `<REDACTED>` in its place. Build loops against env vars, so the credential stays in the environment rather than in what you show. Captured artifacts carry auth headers: quote only the lines that carry the signal.

If the redacted output is not enough to diagnose the bug, say so and ask the user.

## Phase 1: Build a feedback loop

**This is the skill.** Everything else is mechanical. If you have a **tight** pass/fail signal for the bug (one that goes red on _this_ bug), you will find the cause; bisection, hypothesis-testing, and instrumentation all just consume it. If you don't have one, no amount of staring at code will save you.

Spend disproportionate effort here. **Be aggressive. Be creative. Refuse to give up.**

### Ways to construct one, in roughly this order

1. **Targeted Swift Testing test** at the public seam that reaches the bug. Run it with `scripts/xcb test -only-testing:<target/test>`.
2. **Deterministic harness** around a model, repository, service, or view model using a fixed fixture, clock, locale, and model context.
3. **Simulator reproduction** using the worktree simulator reported by `scripts/xcb which-sim`; use `xcrun simctl` only with that resolved device.
4. **Localized reproduction** with the relevant `-testLanguage` and `-testRegion` when strings, parsing, or locale-sensitive behavior matter.
5. **Captured trace, differential run, or bisection harness** when the failure depends on state, data, configuration, or a known version range.
6. **Structured human loop.** When taps, assistive technology, or visual judgment are unavoidable, copy and tailor `scripts/hitl-loop.template.sh`. Record the exact state, actions, and observation.

Build the right feedback loop, and the bug is 90% fixed.

### Tighten the loop

Treat the loop as a product. Once you have _a_ loop, **tighten** it:

- Can I make it faster? (Cache setup, skip unrelated init, narrow the test scope.)
- Can I make the signal sharper? (Assert on the specific symptom, not "didn't crash".)
- Can I make it more deterministic? (Pin time, seed RNG, isolate filesystem, freeze network.)

A warmed targeted test is ideal. A simulator-backed loop may take minutes; accept that only when no narrower seam can reproduce the exact symptom. Prefer the narrowest practical loop over an artificially fast test that cannot fail for the user's bug.

For `scripts/xcb test`, judge the JSON summary rather than the process exit code alone. A compile failure can exit successfully: confirm that the expected tests ran, `totalTestCount` is nonzero, and `failedTests` contains only the intended red signal. Read `.build/test.log` only when the summary is insufficient.

### Non-deterministic bugs

The goal is not a clean repro but a **higher reproduction rate**. Loop the trigger serially, add controlled stress, narrow timing windows, and pin inputs. Do not enable parallel testing; preserve the repository's `scripts/xcb` configuration.

### When you genuinely cannot build a loop

Stop and say so explicitly. List what you tried. Ask for the smallest missing input: access to the reproducing state, a redacted log or screen recording with timestamps, a device/accessibility observation, or permission for temporary instrumentation. Do **not** proceed to hypothesise without an evidence-producing loop.

### Completion criterion: a tight loop that goes red

Phase 1 is done when the loop is **tight** and **red-capable**: name one command or structured human procedure that has already run at least once, with redacted evidence, and that is:

- [ ] **Red-capable**: it drives the actual bug code path and asserts the **user's exact symptom**, so it can go red on this bug and green once fixed. Not "runs without erroring"; it must be able to _catch this specific bug_.
- [ ] **Deterministic**: same verdict every run (flaky bugs: a pinned, high reproduction rate, per above).
- [ ] **Narrow**: no broader or slower than necessary for the real symptom.
- [ ] **Repeatable**: agent-runnable when possible; otherwise driven by a written HITL procedure.

Inspect enough code to locate the correct seam, but do not settle on a causal theory first. No red-capable loop, no Phase 2.

## Phase 2: Reproduce + minimise

Run the loop. Watch it go red as the bug appears.

Confirm:

- [ ] The loop produces the failure mode the **user** described, not a different failure that happens to be nearby. Wrong bug = wrong fix.
- [ ] The failure is reproducible across multiple runs (or, for non-deterministic bugs, reproducible at a high enough rate to debug against).
- [ ] You have captured the exact symptom (error message, wrong output, slow timing) so later phases can verify the fix actually addresses it.

### Minimise

Once it's red, shrink the repro to the **smallest scenario that still goes red**. Cut inputs, callers, config, data, and steps **one at a time**, re-running the loop after each cut, and keep only what's load-bearing for the failure.

Why bother: a minimal repro shrinks the hypothesis space in Phase 3 (fewer moving parts left to suspect) and becomes the clean regression test in Phase 5.

Done when **every remaining element is load-bearing**: removing any one of them makes the loop go green.

Do not proceed until you have reproduced **and** minimised.

## Phase 3: Hypothesise

Generate **3–5 ranked hypotheses** before testing any of them. Single-hypothesis generation anchors on the first plausible idea.

Each hypothesis must be **falsifiable**: state the prediction it makes.

> Format: "If <X> is the cause, then <changing Y> will make the bug disappear / <changing Z> will make it worse."

If you cannot state the prediction, the hypothesis is a vibe: discard or sharpen it.

**Show the ranked list to the user before testing.** They often have domain knowledge that re-ranks instantly ("we just deployed a change to #3"), or know hypotheses they've already ruled out. Cheap checkpoint, big time saver. Don't block on it; proceed with your ranking if the user is AFK.

## Phase 4: Instrument

Each probe must map to a specific prediction from Phase 3. **Change one variable at a time.**

Tool preference:

1. **Debugger / REPL inspection** if the env supports it. One breakpoint beats ten logs.
2. **Targeted logs** at the boundaries that distinguish hypotheses.
3. Prefer boundary-level signposts over broad logging.

**Tag every debug log** with a unique prefix, e.g. `[DEBUG-a4f2]`. Cleanup at the end becomes a single grep. Untagged logs survive; tagged logs die.

**Perf branch.** For performance regressions, logs are usually wrong. Instead: establish a baseline measurement (timing harness, `performance.now()`, profiler, query plan), then bisect. Measure first, fix second.

## Phase 5: Fix + regression test

Write the regression test **before the fix**, but only if there is a **correct seam** for it.

A correct seam is one where the test exercises the **real bug pattern** as it occurs at the call site. If the only available seam is too shallow (single-caller test when the bug needs multiple callers, unit test that can't replicate the chain that triggered the bug), a regression test there gives false confidence.

**If no correct seam exists, that itself is the finding.** Note it. The codebase architecture is preventing the bug from being locked down. Flag this for the next phase.

If a correct seam exists:

1. Turn the minimised repro into a failing test at that seam.
2. Watch it fail.
3. Apply the fix.
4. Watch it pass.
5. Re-run the Phase 1 feedback loop against the original (un-minimised) scenario.

## Phase 6: Cleanup

Required before declaring done:

- [ ] Original repro no longer reproduces (re-run the Phase 1 loop)
- [ ] Regression test passes (or absence of seam is documented)
- [ ] All `[DEBUG-...]` instrumentation removed (`grep` the prefix)
- [ ] Throwaway prototypes deleted (or moved to a clearly-marked debug location)
- [ ] The targeted test summary proves the expected test actually ran
- [ ] Relevant visual, localization, Dynamic Type, and VoiceOver checks were run, or each unrun check is reported explicitly
- [ ] The confirmed root cause is recorded in the authorized handoff, issue, commit, or PR; do not create external updates solely because this skill was used
