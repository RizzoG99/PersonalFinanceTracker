# AGENTS.md

## Project

Personal Finance Tracker is a SwiftUI iOS app for income, expense, budget, insight, import/export, and security workflows.

- Open `PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj` in Xcode for normal development.
- The app directory and target are intentionally spelled `PersonalFinanceTraker` with one `c`.
- Deployment target is iOS 26.0.
- Language and UI stack: Swift 6, SwiftUI, SwiftData, MVVM.
- Tests use Swift Testing (`@Test`, `#expect`) with `@testable import PersonalFinanceTraker`.
- Third-party packages currently include ZIPFoundation and CoreXLSX.

## Codex Workflow

- Read this file before making changes; Claude Code reads `CLAUDE.md`, which should stay aligned with these project facts.
- Use project-local Codex skills from `.codex/skills` when the task matches them:
  - `$swiftui-pro`: SwiftUI code writing, review, architecture, performance, accessibility.
  - `$ios-feature-brainstorm`: feature brainstorming and concise handoff docs.
  - `$ux-audit`: screenshot-based mobile UX/UI audits.
  - `$graphify`: codebase architecture, relationships, and knowledge graph tasks.
- Prefer `rg` and graphify queries before broad source browsing.
- Preserve unrelated user changes in the working tree.
- Keep implementation scoped to the relevant feature folder, model, utility, and test files.

## Build And Test

- Prefer the Xcode MCP connector if it is available in the current Codex session. Load deferred schemas with `tool_search` first, then call the exposed Xcode tools.
- Current Claude tool names, when available in Claude Code, are:
  - Build: `mcp__xcode__BuildProject`
  - Run all tests: `mcp__xcode__RunAllTests`
  - Run specific tests: `mcp__xcode__RunSomeTests`
  - Build/test log: `mcp__xcode__GetBuildLog`
  - Test list: `mcp__xcode__GetTestList`
- Active Claude tab identifier is `windowtab1`.
- Do not invoke MCP tool names as shell commands.
- Do not run shell `xcodebuild` unless the user explicitly asks for it or approves it for the turn.

## App Conventions

- Expenses are stored as negative `Decimal`; income is positive.
- Convert money to `Double` only at display or chart boundaries.
- EUR is currently hardcoded throughout the app.
- Use `SampleData.populateModelContext()` in previews and tests.
- Categories are stored as strings in the form `"emoji label"`.
- Search and filters live in the Activity tab:
  - `.searchable` handles text search.
  - Type/date/amount filter chips live in `FilterChipsView`.
  - Filter semantics live in `SearchFilters.matches` in `Models/TransactionRepository.swift`.
  - Coverage lives in `SearchTests`.

## Architecture Map

- App entry/composition: `PersonalFinanceTraker/PersonalFinanceTraker/App`
- Features: `PersonalFinanceTraker/PersonalFinanceTraker/Features`
- Models and repositories: `PersonalFinanceTraker/PersonalFinanceTraker/Models`
- Services and helpers: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities`
- Unit tests: `PersonalFinanceTraker/PersonalFinanceTrakerTests`
- UI tests: `PersonalFinanceTraker/PersonalFinanceTrakerUITests`
- Feature ideas and handoff docs: `docs/features`
- Implementation plans/specs: `docs/superpowers`

## graphify

This project has a knowledge graph at `graphify-out/`.

- For codebase questions, first run `graphify query "<question>"` when `graphify-out/graph.json` exists.
- Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts.
- If `graphify-out/wiki/index.md` exists, use it for broad navigation instead of raw source browsing.
- Read `graphify-out/GRAPH_REPORT.md` only for broad architecture review or when query/path/explain does not surface enough context.
- After modifying code, run `graphify update .` if graphify is available and the user has not asked to skip it.
