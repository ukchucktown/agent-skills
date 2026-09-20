# Agent Skills

Personal Agent Skills and deterministic workflow helpers for Codex, Claude
Code, and GitHub Copilot.

This private repository keeps installable skills, shared instruction fragments,
and cross-harness workflow scripts in one maintained source. Each skill remains
independently selectable so that an agent session loads only the capabilities
needed for its task.

## Skills

| Skill | Status | Purpose |
|---|---|---|
| [`first-read`](skills/writing/first-read/) | Promoted | Write and audit durable technical prose |
| [`sdlc-cancel-feature`](skills/engineering/sdlc-cancel-feature/) | Promoted | Plan and apply a safe feature cancellation |
| [`sdlc-finish-issue`](skills/engineering/sdlc-finish-issue/) | Promoted | Validate, review, and merge one child issue |
| [`sdlc-finish-feature`](skills/engineering/sdlc-finish-feature/) | Promoted | Prepare and approve the final feature merge |
| [`sdlc-plan-work`](skills/engineering/sdlc-plan-work/) | Promoted | Plan and publish one issue or a coordinated feature |
| [`sdlc-setup`](skills/engineering/sdlc-setup/) | Promoted | Configure repositories and GitHub PR contracts |
| [`sdlc-start-issue`](skills/engineering/sdlc-start-issue/) | Promoted | Claim an issue and prepare its isolated worktree |
| [`sdlc-status`](skills/engineering/sdlc-status/) | Promoted | Show live workflow status and the next command |
| [`sdlc-workflow`](skills/engineering/sdlc-workflow/) | Internal | Share lifecycle rules and safe runtime contracts |

Promoted engineering and writing skills live in subject buckets. Unfinished
and retired skills live in the `in-progress` and `deprecated` lifecycle
buckets. Repository checks enforce the bucket, name, metadata, and local-link
rules.

## Install one skill

The [Skills CLI](https://github.com/vercel-labs/skills) can discover each skill
below `skills/`:

```bash
npx skills add ukchucktown/agent-skills --skill first-read --global --yes
```

Use `--agent` to limit the target harness. Use `--copy` for a detached copy or
omit it for a link that follows this checkout. See the
[`first-read` guide](docs/first-read/README.md) for its extra integrations.

## Develop

Requirements:

- Node.js 20 or later
- Python 3.8 or later for the First Read linter

Run all checks:

```bash
npm ci
npm test
```

Read [CONTRIBUTING.md](CONTRIBUTING.md) before a change. Read the
[private release process](docs/releases.md) before a version update.
