---
name: sdlc-cancel-feature
description: Plan and apply cancellation of a coordinated SDLC feature with an exact approval boundary and conservative cleanup. Use when the user asks to cancel, abandon, or stop a coordinated feature and review every issue, pull request, worktree, and branch affected.
disable-model-invocation: true
---

# SDLC cancel feature

Run this skill from the stable checkout. Cancellation uses two separate steps.

## Plan

```bash
node skills/engineering/sdlc-cancel-feature/scripts/cancel-feature.mjs plan \
  --repository . \
  --feature <number> \
  --output /tmp/sdlc-cancel-plan.json
```

Show the complete plan to the user. It lists each open pull request and issue
that would close. It also classifies every worktree as removable or retained.
Cancellation retains work unless Git proves that its branch already reached
the stable branch and the worktree is clean.

## Approval boundary

Do not apply the plan until the user explicitly approves that exact plan. Pass
its `planId` after approval:

```bash
node skills/engineering/sdlc-cancel-feature/scripts/cancel-feature.mjs apply \
  --repository . \
  --plan /tmp/sdlc-cancel-plan.json \
  --approved <planId>
```

The command inspects shared and local state again. It stops when the plan is
stale or changed. It then closes only the listed pull requests and issues. It
keeps dirty, unmerged, detached, or ambiguous work and includes every retained
item in the result.
