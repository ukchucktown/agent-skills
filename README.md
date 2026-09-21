# Agent Skills

Personal Agent Skills and deterministic workflows for Codex, Claude Code, and
GitHub Copilot.

Skills under `skills/in-progress/` are reviewable but not yet promoted for
general installation. Promoted skills remain independently selectable.

Current work:

- `skills/engineering/gh-issue` — lightweight GitHub issue mechanics with a
  bounded status query and deterministic issue worktree setup. `finish` and
  `clean` remain intentionally unavailable until their implementations are
  reviewed.

Install a selected skill with the standard Agent Skills CLI:

```text
npx skills@latest add ukchucktown/agent-skills
```

For a global, non-interactive installation of `gh-issue` across the initial
supported harnesses, run:

```text
npx skills@latest add ukchucktown/agent-skills --skill gh-issue --agent codex --agent claude-code --agent github-copilot --global --yes
```

The CLI uses existing Git or GitHub CLI authentication for this private
repository. Use `npx skills list`, `npx skills update`, and `npx skills remove`
to manage installed skills.
