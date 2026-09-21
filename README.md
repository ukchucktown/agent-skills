# Agent Skills

Personal Agent Skills and deterministic workflows for Codex, Claude Code, and
GitHub Copilot.

Skills under `skills/in-progress/` are reviewable but not yet promoted for
general installation. Promoted skills remain independently selectable.

Current work:

- `skills/engineering/gh-issue` — lightweight GitHub issue mechanics with a
  bounded status query, direct issue worktree setup, unmerged pull-request
  preparation, completed no-change handoff, and guarded cleanup for merged
  issue efforts.

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

The `gh-issue` commands require Git, GitHub CLI, and `jq`. The start command
can use Supacode when the global configuration selects it. It can also add
personal repository issues to one configured GitHub Project and set them to
`In Progress`; GitHub Project workflows can set closed issues to `Done`.
