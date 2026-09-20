---
name: sdlc-workflow
description: Shared lifecycle rules and deterministic runtime for coordinated GitHub feature work. Use when an sdlc-* skill needs repository configuration, workflow state, next-action derivation, plan freshness checks, or safe GitHub, Git, and worktree action boundaries. This is an internal skill; prefer the explicit sdlc-* entry-point skills for user requests.
---

# SDLC workflow

Use this skill as the shared source of truth for the `sdlc-*` workflow. Keep the
user at an explicit entry point such as `sdlc-plan-work`, `sdlc-status`, or
`sdlc-start-issue`.

## Read the workflow

1. Read [the lifecycle](references/lifecycle.md) for states and transitions.
2. Read [the runtime contract](references/runtime-contract.md) before a script
   creates or applies a plan.
3. Read the JSON schemas only when a configuration or runtime value needs
   inspection.

## Use the runtime

Run the dependency-free Node.js entry point from a repository checkout:

```bash
node skills/engineering/sdlc-workflow/scripts/sdlc.mjs inspect \
  --repository . \
  --github-snapshot github.json \
  --worktree-snapshot worktrees.json \
  --feature 148
```

The `inspect` and `plan` commands print canonical JSON. A caller can use
`--output <file>` when it needs a reviewable artifact.

Never mutate from an inspection result alone. Create an action plan with the
observed state fingerprint. At apply time, inspect the live sources again and
pass the new state to `applyPlan`. The engine rejects a stale fingerprint
before it calls an adapter.

## Preserve the boundaries

- Treat GitHub as the shared workflow source of truth.
- Treat repository and machine configuration as preferences, not workflow
  state.
- Pass structured action values to adapters. Never pass a shell string.
- Keep all inspection commands read-only.
- Keep plan creation free of side effects.
- Require explicit approval for the final integration-to-stable merge.
- Keep child worktrees until the full feature reaches the stable branch.

The runtime does not call GitHub, Git, Supacode, or the filesystem mutation
APIs directly. Entry-point skills provide adapters for those effects.
