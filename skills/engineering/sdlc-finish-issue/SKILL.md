---
name: sdlc-finish-issue
description: Validate, review, open, and safely merge one coordinated SDLC child issue into its recorded integration branch. Use when the user says finish issue followed by a number, asks to prepare a child pull request, or wants to merge completed child work.
disable-model-invocation: true
---

# SDLC finish issue

Finish one coordinated child. Do not use this skill for a pull request that
targets the stable branch.

## Prepare the candidate

1. Commit the complete issue-scoped change.
2. Run the preparation command from the issue worktree:

```bash
node skills/engineering/sdlc-finish-issue/scripts/finish-issue.mjs prepare \
  --repository . \
  --issue <number> \
  --output /tmp/sdlc-finish-candidate.json
```

The command rejects a dirty worktree, a wrong branch, an open blocker, and a
stable-branch target. It runs the configured child validation commands without
a shell and records the exact candidate commit.

## Review the candidate

Invoke the installed `code-review` skill against the candidate commit and the
recorded integration branch. Complete both axes:

- Standards: repository guidance and documented coding standards
- Specification: the child issue and its acceptance criteria

Write one JSON evidence file for each axis. Follow
`references/review-evidence.md`. A failing review stops the workflow. If the
candidate commit changes, prepare and review it again.

## Finish the child

```bash
node skills/engineering/sdlc-finish-issue/scripts/finish-issue.mjs finish \
  --repository . \
  --issue <number> \
  --standards-review /tmp/standards-review.json \
  --specification-review /tmp/specification-review.json
```

The command reruns validation for the reviewed commit. It pushes that exact
commit, creates or updates the pull request, and targets the recorded
integration branch. The generated body closes only the child issue and records
both review summaries.

GitHub review decisions and check results remain authoritative. The command
waits for them and verifies that the pull request head is still the reviewed
commit. When child auto-merge is enabled, it uses the configured child merge
method and closes the issue after a successful merge. When auto-merge is off,
it reports `ready_for_merge` and stops.

## Handoff

Report the candidate commit, pull request, target integration branch, merge
method, validation result, and whether the issue closed. Keep the worktree
until the full feature reaches the stable branch.
