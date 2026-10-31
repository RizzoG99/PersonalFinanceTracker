# CLAUDE.md

## Agent Setup

This repository is configured for both Claude Code and Codex.

- Claude Code reads this `CLAUDE.md`.
- Codex reads `AGENTS.md`.
- Shared project skills live canonically in `.agents/skills`.
- `.claude/skills` and `.codex/skills` contain relative symlinks for native discovery. Edit only `.agents/skills`; when adding a shared skill, add a symlink for each supported agent.
- Keep shared project facts aligned between this file and `AGENTS.md`; keep tool-specific instructions in the file for that tool.

Shared project skills include `$swiftui-pro`, `$feature-brainstorm`, `$ux-audit`, `$graphify`, `$diagnosing-bugs`, `$performance-audit`, `$performance-profiling`, `$retro`, `$writing-for-agents`, `$pft-pr-lifecycle`, and `$testflight-feedback`. Use `$diagnosing-bugs` for uncertain regressions, `$performance-audit` for audit-only repository-wide performance investigations, `$performance-profiling` for one specific slowness complaint, `$retro` for an explicitly requested coding-session retrospective, `$writing-for-agents` for agent-facing documentation, `$pft-pr-lifecycle` for explicitly requested issue-to-PR delivery, and `$testflight-feedback` for periodic triage of TestFlight feedback into GitHub issues.

For every new or materially changed user-facing view, use `$swiftui-pro` before implementation. Inspect the two closest existing screens/components and follow its `references/design.md` preflight and quality gate. Do not call UI work complete without checking app-theme consistency, relevant UI states, light/dark appearance, compact and wide layouts, accessibility Dynamic Type, and VoiceOver semantics. Report any check that could not be run.

## Changelog

Before opening a PR for a user-facing feature or fix, append one bullet to the
`## Unreleased` section of `CHANGELOG.md`, in plain language a tester would
understand (what changed for them, not implementation detail). Skip it only
for changes with no visible effect (refactors, tooling, tests).

`scripts/xcb release-notes` sends that section to TestFlight as "What to
Test" and archives it under the shipped build number — the changelog is the
only source for that, so a skipped bullet means testers get no notes.

## Automation

- CI (`.github/workflows`): `ci.yml` runs `scripts/xcb test` on PRs and fails unless tests actually ran; `changelog.yml` requires a `CHANGELOG.md` change on `feature/*`/`fix/*` PRs (`no-changelog` in the PR body opts out); `deps.yml` opens an issue when ZIPFoundation or CoreXLSX has a newer release.
- `.swiftformat` is whitespace-only on purpose (default rules would rewrite most files); keep it that way.
- Shared scripts in `.claude/hooks`: `git-guard.sh` blocks commits on `main` in the primary checkout, bad branch names, `gh pr create` without a changelog change (`PFT_SKIP_CHANGELOG=1` to skip), and AI attribution in commits/PRs/comments; `graphify-update.sh` refreshes the graph on Stop. Claude Code wires these in `.claude/settings.json`; Codex enables them through `.codex/config.toml` and `.codex/hooks.json`, with user approval through `/hooks`. Claude Code also runs `swiftformat` on edited Swift files through a PostToolUse hook.

## Branch Naming

Git-flow style, always: `feature/<slug>`, `fix/<slug>`, `chore/<slug>` —
prefix with the issue number when one exists (`fix/148-bulk-category-select-all`,
`feature/47-category-type-uniqueness`). This applies to worktree branches too:
when creating a worktree (`EnterWorktree` or `git worktree add`), name the
branch by what it does, never `worktree-<anything>` — that's a directory
name, not a branch name, and it has slipped in repeatedly.

## Build & Development Commands

**Use the `xcodebuild` CLI. It is the default for agents.** The Xcode MCP is optional and has three failure modes that cost real time:

- A **crashed test** leaves the MCP waiting forever — no exit code, no timeout. The agent gets stuck polling.
- It **requires Xcode open and connected**. The CLI is headless.
- With **worktrees**, `tabIdentifier` gets reassigned between windows and the MCP silently builds the *wrong worktree*.

```bash
scripts/xcb build
scripts/xcb test
scripts/xcb test -only-testing:PersonalFinanceTrakerTests/SearchTests
scripts/xcb scenarios HarnessSmokeScenarioTests   # acceptance-scenario UI tests, iPhone + iPad
scripts/xcb which-sim    # print this worktree's simulator name + UDID
scripts/xcb clean-sims   # delete leftover "Clone N of ..." simulators
scripts/xcb delete-sim   # drop this worktree's dedicated simulators
```

`scripts/xcb test` prints only a JSON summary (counts, failed test names, messages); the full log goes to `.build/test.log`. Read that file only when the summary is not enough.

**Verify UI work with scenario tests.** `scripts/xcb scenarios [UITestClass]` runs `ScenarioTestCase` subclasses on iPhone and iPad. With no class it runs every `*ScenarioTests` class, which is the regression run. It prints a JSON summary, and screenshots land in `.build/scenarios/shots/` for review. The mechanics live in `ScenarioTestCase.swift` and the script.
- Scenario tests are XCTest, because XCUITest requires it. The Swift Testing rule covers unit tests only.
- They skip themselves under plain `scripts/xcb test` and in CI.
- A failed test is retried once. One that passes on retry keeps `result` at `Passed`, but the summary lists it under `flaky` with its first failure. Report every `flaky` entry, for example in the PR's Limitations. `HarnessRetryProbe` checks this mechanism.
- A pre-existing accessibility finding gets its own GitHub issue first, then an entry in `knownAccessibilityIssues` that points to it.
- Check launch-state changes through a scenario test. `simctl launch` renders a blank screen once a PIN is set.

**Run builds and tests in the background** (`run_in_background: true`), then wait with a `Monitor` until-loop. A full test run takes several minutes and will otherwise eat a foreground timeout.

**One simulator run at a time, machine-wide.** `scripts/xcb test` and `scenarios` take a kernel `flock` on `/tmp/pft-xcb-simulator.lock`. A run started from another worktree waits for it ("waiting for another simulator run…"). Don't kill a waiting run, and never delete the file. The lock is released when the holder's processes exit, however they exit. `test` shuts its simulator down afterwards if the run booted it. Both commands list other booted simulators, which hold memory, but they never shut those down.

Notes:
- **Everything is per-worktree, no configuration.** `-derivedDataPath .build` is relative, so each worktree gets its own build tree (`.build/` is gitignored), and the script creates its own simulator named `pft-<worktree-dir>` on first use, so concurrent agents never share a device. `PFT_SIM_UDID=<udid>` overrides it.
- **Never hardcode a simulator OS version.** `simctl`'s runtime *identifier* is rounded (`iOS-26-4`) while its real version is `26.4.1`, and a bare `name=iPhone 17` destination expands to `OS:latest`, which can resolve to a runtime that has no such device. The script targets the device by UDID, which avoids both. If you write a destination by hand, get it from `xcodebuild -showdestinations`, never from `simctl list devices`.
- **Never call MCP tool names as Bash commands.** `mcp__xcode__BuildProject` is not a shell command.

**If you do use the MCP** (Xcode already open, single checkout): schemas are deferred, so load them with `ToolSearch` first — `query: "select:mcp__xcode__BuildProject,mcp__xcode__RunAllTests"` — then call with `tabIdentifier: "windowtab1"`. Verify the identifier with `mcp__xcode__XcodeListWindows` first; match on `WorkspacePath`, not the first hit.

**Note**: The project is primarily developed in Xcode. Open `PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj` to work in the IDE.

## Project

- Personal Finance Tracker is a SwiftUI iOS app for income, expense, budget, insight, import/export, and security workflows.
- Deployment target: iOS 26.0.
- Stack: Swift 6, SwiftUI, SwiftData, MVVM.
- Third-party packages currently include ZIPFoundation and CoreXLSX.
- Source root: `PersonalFinanceTraker/PersonalFinanceTraker`.
- Unit tests: `PersonalFinanceTraker/PersonalFinanceTrakerTests`.
- UI tests: `PersonalFinanceTraker/PersonalFinanceTrakerUITests`.

## Gotchas

- **Typo**: Directory is `PersonalFinanceTraker` (missing 'c' in Tracker)
- **Amounts**: expenses stored as **negative** `Decimal`; convert to `Double` for display only
- **Currency**: EUR hardcoded throughout
- **Testing**: Swift Testing (`@Test`, `#expect`), NOT XCTest; `@testable import PersonalFinanceTraker`
- **Sample data**: `SampleData.populateModelContext()` — use in previews and tests
- **Search & filters**: live in the Activity tab — text search via `.searchable`, plus type/date/amount filter chips (`FilterChipsView`); filter semantics in `SearchFilters.matches` (`Models/TransactionRepository.swift`), covered by `SearchTests`

## graphify

Graphify generates a local knowledge graph at `graphify-out/`. The directory is ignored by Git and belongs to the worktree that generated it; never stage, commit, or share it between worktrees.

Rules:
- For codebase questions, first run `graphify query "<question>"` when `graphify-out/graph.json` exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than `GRAPH_REPORT.md` or raw grep output.
- If `graphify-out/wiki/index.md` exists, use it for broad navigation instead of raw source browsing.
- Read `graphify-out/GRAPH_REPORT.md` only for broad architecture review or when query/path/explain do not surface enough context.
- On a fresh worktree without a graph, use `rg` for initial navigation or generate the graph locally.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost). The update must leave Git status unchanged.
- Graphify results describe the checkout that generated them and may be stale after switching branches or commits.
