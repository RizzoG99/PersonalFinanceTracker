---
name: graphify
description: Uses graphify for codebase questions, architecture exploration, file relationships, project-content queries, and knowledge graph maintenance when graphify-out exists or the user invokes graphify-style analysis.
---

# graphify

Use graphify as the first navigation layer for this repository when the question is about architecture, relationships, or codebase content.

## Fast Path

If `graphify-out/graph.json` exists and the user asks a natural-language question about the codebase, run:

```bash
graphify query "<question>"
```

Use the result to choose source files to read next. Do not read the full graph JSON manually for ordinary questions.

## Commands

```bash
graphify query "<question>"
graphify path "<A>" "<B>"
graphify explain "<concept>"
graphify update .
```

Use `graphify path` for relationships and `graphify explain` for focused concepts.

## Maintenance

- After modifying code, run `graphify update .` when graphify is installed and the user has not asked to skip it.
- If graphify is unavailable or blocked by sandbox/network limits, continue with `rg` and source reading, and mention the skipped graph update.
- Read `graphify-out/GRAPH_REPORT.md` only for broad architecture review or when query/path/explain is insufficient.

## Extended Workflows

For rebuilding, adding sources, exports, hooks, transcription, and GitHub imports, load only the relevant reference file from `references/`.
