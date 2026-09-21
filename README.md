# Agent Skills

This repository contains personal Agent Skills and deterministic workflows for
Codex, Claude Code, and GitHub Copilot.

## Available skills

| Skill | Purpose | Documentation |
|---|---|---|
| `gh-issue` | Manage the mechanics of GitHub issue work from start through pull-request handoff and cleanup. | [Read the `gh-issue` guide](docs/gh-issue.md) |

Skills under `skills/in-progress/` are available for review but are not ready
for general installation. Each promoted skill remains independently
selectable.

## Install a skill

Use the standard Agent Skills CLI to select skills and target agents:

```text
npx skills@latest add ukchucktown/agent-skills
```

Use this command to install `gh-issue` globally for Codex, Claude Code, and
GitHub Copilot without prompts:

```text
npx skills@latest add ukchucktown/agent-skills --skill gh-issue --agent codex --agent claude-code --agent github-copilot --global --yes
```

The CLI uses your Git or GitHub CLI authentication for this private repository.
Use `npx skills list`, `npx skills update`, and `npx skills remove` to manage
installed skills.
