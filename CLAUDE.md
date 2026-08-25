# CLAUDE.md

## Agent Setup

This repository is configured for both Claude Code and Codex.

- Claude Code reads this `CLAUDE.md`.
- Codex reads `AGENTS.md`.
- Shared project skills live canonically in `.agents/skills`.
- `.claude/skills` and `.codex/skills` contain relative symlinks for native discovery. Edit only `.agents/skills`; when adding a shared skill, add a symlink for each supported agent.
- Keep shared project facts aligned between this file and `AGENTS.md`; keep tool-specific instructions in the file for that tool.

For every new or materially changed user-facing view, use `$swiftui-pro` before implementation. Inspect the two closest existing screens/components and follow its `references/design.md` preflight and quality gate. Do not call UI work complete without checking app-theme consistency, relevant UI states, light/dark appearance, compact and wide layouts, accessibility Dynamic Type, and VoiceOver semantics. Report any check that could not be run.

## Build & Development Commands

**Use the `xcodebuild` CLI. It is the default for agents.** The Xcode MCP is optional and has three failure modes that cost real time:

- A **crashed test** leaves the MCP waiting forever — no exit code, no timeout. The agent gets stuck polling.
- It **requires Xcode open and connected**. The CLI is headless.
- With **worktrees**, `tabIdentifier` gets reassigned between windows and the MCP silently builds the *wrong worktree*.

```bash
scripts/xcb build
scripts/xcb test
scripts/xcb test -only-testing:PersonalFinanceTrakerTests/SearchTests
scripts/xcb which-sim    # print this worktree's simulator name + UDID
scripts/xcb clean-sims   # delete leftover "Clone N of ..." simulators
scripts/xcb delete-sim   # drop this worktree's dedicated simulator
```

`scripts/xcb test` prints only a JSON summary (counts, failed test names, messages); the full log goes to `.build/test.log`. Read that file only when the summary is not enough.

**Run builds and tests in the background** (`run_in_background: true`), then wait with a `Monitor` until-loop. A full test run takes several minutes and will otherwise eat a foreground timeout.

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

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
