# Shared Agent Skills

`.agents/skills` is the canonical source for project skills shared by coding agents.

- Codex's project entry point is `AGENTS.md`; Claude Code's is `CLAUDE.md`.
- Edit skill instructions and resources only in `.agents/skills/<skill>`.
- `.codex/skills/<skill>` and `.claude/skills/<skill>` are relative symlinks used for each tool's native discovery.
- When supporting another coding agent, add the smallest tool-specific symlink or adapter that points to the canonical skill; do not copy the skill directory.
- Tool-specific metadata may stay inside a shared skill when other agents safely ignore it. Keep genuinely tool-specific instructions in that tool's project instruction file.
- Verify symlinks resolve from a clean checkout after adding, renaming, or removing a skill.
- Keep shared project facts aligned between `AGENTS.md` and `CLAUDE.md`; keep genuinely tool-specific instructions in the relevant entry point.

This layout provides one editable source of truth without depending on every agent to discover the same neutral directory automatically.
