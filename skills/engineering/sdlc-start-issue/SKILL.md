---
name: sdlc-start-issue
description: Claim or resume one ready SDLC child issue and prepare its isolated worktree. Use when the user says start issue followed by a number, asks to pick up a ready child, or wants the configured Supacode or native Git worktree for an issue.
disable-model-invocation: true
---

# SDLC start issue

Prepare the issue environment and stop. Do not implement the issue in this
skill invocation.

## Start or resume

Run from the repository checkout:

```bash
node skills/engineering/sdlc-start-issue/scripts/start-issue.mjs start \
  --repository . \
  --issue <number>
```

The command verifies all of these conditions before a side effect:

- the issue is an open child of a configured feature
- every native blocker is closed
- the integration branch exists
- no pull request exists for the child branch
- no other person owns the issue

It then creates or reuses the configured worktree, assigns the current GitHub
user, removes the ready label, and records the branch on the issue. The issue
comment never contains a local path.

## Resolve an assignment conflict

Stop and show the existing assignees. Continue only after the user gives an
explicit takeover reason. Record that reason with the override:

```bash
node skills/engineering/sdlc-start-issue/scripts/start-issue.mjs start \
  --repository . \
  --issue <number> \
  --override-assignment "The assignee asked me to continue this issue."
```

Do not infer consent from an inactive branch or an old assignment.

## Handoff

Report the issue, branch, integration base, worktree manager, worktree ID, and
local worktree path. Then stop so that the next coding session can start in the
prepared environment.
