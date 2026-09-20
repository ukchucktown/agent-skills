---
name: sdlc-status
description: Report read-only SDLC workflow status and the exact next valid command. Use when the user asks for status, progress, what is blocked or ready, what to do next, the next issue or feature action, or status across all configured repositories.
disable-model-invocation: true
---

# SDLC status

Read live GitHub and Git worktree evidence. Do not create, edit, or close
anything.

## Current repository

Run from the repository checkout:

```bash
node skills/engineering/sdlc-status/scripts/status.mjs --repository .
```

Use `--feature <number>` when the repository has several open coordinated
features. Add `--json` for canonical machine-readable output.

## All configured repositories

```bash
node skills/engineering/sdlc-status/scripts/status.mjs --all
```

The command searches only direct children of the configured `checkoutRoot`.
It includes a repository only when `docs/agents/sdlc.md` exists. It never scans
the full home directory.

## Report

For each feature, report:

- the feature state and integration branch
- blocked child issues and their open blockers
- ready child issues
- active child issues, including review work
- complete child issues
- evidence warnings
- the exact next `sdlc-*` command, or a clear statement that no valid command
  exists until an external blocker changes

Use `/sdlc-start-issue <number>` for both a ready child and a resumable active
child. The start skill reuses the prepared branch and worktree when they exist.
