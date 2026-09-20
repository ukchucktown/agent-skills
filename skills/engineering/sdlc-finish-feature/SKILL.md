---
name: sdlc-finish-feature
description: Validate an integrated SDLC feature, prepare its stable-branch pull request, require explicit final approval, and clean only verified worktrees. Use when all child issues are complete or the user asks to finish, approve, or merge a coordinated feature.
disable-model-invocation: true
---

# SDLC finish feature

Run this skill from the repository's stable checkout. Keep the integration and
child worktrees until the final pull request merges.

## Prepare the integrated candidate

1. Confirm that every child issue is closed by a pull request that merged into
   the recorded integration branch.
2. Run the preparation command. It uses the integration worktree for full
   validation and records its exact commit.

```bash
node skills/engineering/sdlc-finish-feature/scripts/finish-feature.mjs prepare \
  --repository . \
  --feature <number> \
  --output /tmp/sdlc-feature-candidate.json
```

3. Compare the complete integrated change with the parent issue and accepted
   specification. Record the result as specification review evidence for the
   candidate commit.

## Submit the final pull request

```bash
node skills/engineering/sdlc-finish-feature/scripts/finish-feature.mjs submit \
  --repository . \
  --feature <number> \
  --specification-review /tmp/feature-specification-review.json
```

The command reruns full validation, pushes the exact integration commit, and
creates or updates a pull request to the configured stable branch. Its body
closes only the parent feature. It does not merge the pull request.

## Prepare the approval plan

After GitHub checks and reviews pass, create the final merge plan:

```bash
node skills/engineering/sdlc-finish-feature/scripts/finish-feature.mjs merge-plan \
  --repository . \
  --feature <number> \
  --specification-review /tmp/feature-specification-review.json \
  --output /tmp/sdlc-feature-merge-plan.json
```

Show the complete plan to the user. Include the pull request, candidate commit,
merge method, and every worktree that the cleanup would remove or retain.

## Approval boundary

Do not run the merge command until the user explicitly approves that exact
plan. Then pass the approved `planId`:

```bash
node skills/engineering/sdlc-finish-feature/scripts/finish-feature.mjs merge \
  --repository . \
  --plan /tmp/sdlc-feature-merge-plan.json \
  --approved <planId>
```

The command rejects changed plan content or live state. After a successful
merge, it removes only clean worktrees with complete merge evidence. It keeps
dirty, unmerged, detached, or ambiguous work and reports the reason.
