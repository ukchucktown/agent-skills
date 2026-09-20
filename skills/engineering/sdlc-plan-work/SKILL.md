---
name: sdlc-plan-work
description: Plan new or resumed GitHub work as one issue or a coordinated feature. Use when the user asks to plan, scope, start a new effort, turn a specification into issues, resume an unfinished plan, or decide whether work needs the full integration-branch workflow.
disable-model-invocation: true
---

# SDLC plan work

Start here for a new issue or task, even when the repository already uses the
workflow. Skip every stage that current repository and GitHub evidence proves
complete.

## Choose the work shape

Ask the user to choose one of these paths:

1. One issue with one reviewable outcome.
2. A coordinated feature with a parent specification, dependency-ordered child
   issues, and an integration branch.
3. Help to decide between the two.

Use one issue when the work fits one pull request and has no useful independent
delivery slices. Use a coordinated feature when several pull requests need a
shared specification, dependency order, or final integration review.

## Recover current progress

Inspect before a new interview:

- If `docs/agents/sdlc.md` is absent, hand off to `/sdlc-setup`.
- If repository setup is current, skip setup.
- If an issue or approved specification already answers a planning stage, show
  that evidence and skip the stage.
- If child issues and native dependencies match the approved delivery plan,
  report `/sdlc-status` as the next command.

Do not create a second parent for a resumed effort.

## Use the Matt skill handoffs

For engineering work, default to `/grill-with-docs`. Use `/grill-me` only when
the repository has no useful documents. Give the interview the selected work
shape, repository context, constraints, and known artifacts.

After the interview:

1. Hand the findings to `/to-spec`.
2. Present the specification for explicit user approval.
3. For a coordinated feature, hand the approved specification to
   `/to-tickets`.
4. Present the dependency graph and issue bodies for separate user approval.

These are explicit handoffs because user-invoked skills do not invoke one
another. After each handoff, return to `/sdlc-plan-work` with the produced
artifact or its GitHub issue number.

## Publish approved work

Create a publisher input JSON after both approval boundaries. Run plan mode and
show the canonical issue plan:

```bash
node skills/engineering/sdlc-plan-work/scripts/publish-plan.mjs plan \
  --repository-root . \
  --input /tmp/sdlc-work.json \
  --output /tmp/sdlc-publish-plan.json
```

After the user approves that exact plan, apply it with its plan ID:

```bash
node skills/engineering/sdlc-plan-work/scripts/publish-plan.mjs apply \
  --plan /tmp/sdlc-publish-plan.json \
  --approved <plan-id>
```

The publisher creates one parent specification, child issues in dependency
order, native subissue links, and native blockers. It uses markers to make a
retry idempotent.

Finish with the parent and child links and the exact next command:
`/sdlc-status --feature <parent-number>` or `/sdlc-start-issue <issue-number>`.
