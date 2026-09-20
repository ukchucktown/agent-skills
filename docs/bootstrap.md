# Personal skill bootstrap

The bootstrap prepares Codex, Claude Code, and GitHub Copilot from one local
checkout. It creates a machine profile, adds links to promoted skills, and
synchronizes one managed instruction block in each harness instruction file.
It preserves content outside the managed block.

Lampwright remains the source of truth for skill availability. The bootstrap
reads Lampwright's disabled storage and does not recreate a disabled skill.

## Review and apply a bootstrap plan

Create a plan from the `agent-skills` checkout:

```bash
npm run bootstrap -- plan --repository . --output bootstrap-plan.json
```

Review `bootstrap-plan.json`. It reports existing links, instruction drift,
conflicts, and Lampwright-disabled targets. Apply the unchanged plan:

```bash
npm run bootstrap -- apply --plan bootstrap-plan.json
```

The default profile uses Supacode and these locations:

| Harness | Skill location | Instruction file |
|---|---|---|
| Codex | `~/.agents/skills` | `~/.codex/AGENTS.md` |
| Claude Code | `~/.claude/skills` | `~/.claude/CLAUDE.md` |
| GitHub Copilot | `~/.agents/skills` | `~/.copilot/copilot-instructions.md` |

The profile is stored at `~/.config/agent-skills/config.json`. Edit that file
to override `checkoutRoot`, `worktreeRoot`, `worktreeManager`, executable
names, source paths, Lampwright state, or harness paths. The workflow supports
`supacode` and `git` as worktree managers.

Use `--worktree-manager git` or `--lampwright-state <path>` to create a profile
with different defaults. Use `--home <path>` or `--config <path>` for an
isolated setup.

## Install a selected set

Pass a comma-separated list when only some skills are needed:

```bash
npm run bootstrap -- plan --repository . --skills first-read,sdlc-status --output bootstrap-plan.json
```

The bootstrap adds `sdlc-workflow` when the selection contains an SDLC entry
point. The shared runtime is user-invoked and does not opt in to implicit model
invocation.

The Skills CLI can also install and remove skills by name. Install a standalone
skill:

```bash
npx skills add ukchucktown/agent-skills --skill first-read --global --yes
```

Install one SDLC entry point with its shared runtime:

```bash
npx skills add ukchucktown/agent-skills --skill sdlc-status sdlc-workflow --global --yes
```

Remove one skill and leave the others unchanged:

```bash
npx skills remove --global first-read --yes
```

Keep `sdlc-workflow` while another installed SDLC entry point needs it. Use
Lampwright to disable or enable installed skills across harnesses. A later
bootstrap run respects that disabled state.

## Check shared instructions

Report instruction drift. The command leaves each file unchanged:

```bash
npm run instructions:sync -- check --repository .
```

The check exits with status 2 when a managed block differs from the source. Apply the
current shared fragment with:

```bash
npm run instructions:sync -- apply --repository .
```

Both commands accept `--machine-config <path>`.

## Update Matt Pocock skill dependencies

The repository records the exact tested revision and selected skill paths in
`dependencies/mattpocock.json`. Check upstream and open an update pull request
with one command:

```bash
npm run matt:update
```

The command validates every selected `SKILL.md` at the new commit before it
creates a branch or pull request. It reports `current` and creates nothing when
the tested revision is already current.
