# CLAUDE.md

## Build & Development Commands

**CRITICAL — BUILD & TEST RULES:**
- **NEVER run `xcodebuild` in Bash.** It is banned. Use Xcode MCP tools only.
- **NEVER call MCP tool names as Bash commands.** `mcp__xcode__BuildProject` is not a shell command.
- MCP tools are deferred — their schemas must be loaded with `ToolSearch` before they can be called.

**Exact two-step sequence every time:**

Step 1 — load the schema via `ToolSearch`:
```
query: "select:mcp__xcode__BuildProject,mcp__xcode__RunAllTests,mcp__xcode__RunSomeTests"
```

Step 2 — call the tool with `tabIdentifier: "windowtab1"`:
```
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")
```

| Task | MCP tool name |
|------|--------------|
| Build | `mcp__xcode__BuildProject` |
| Run all tests | `mcp__xcode__RunAllTests` |
| Run specific tests | `mcp__xcode__RunSomeTests` |
| Get build/test log | `mcp__xcode__GetBuildLog` |
| List available tests | `mcp__xcode__GetTestList` |

The active `tabIdentifier` is always `"windowtab1"`.

**Note**: The project is primarily developed in Xcode. Open `PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj` to work in the IDE.

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
