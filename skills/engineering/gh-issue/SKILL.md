---
name: gh-issue
description: Manage existing GitHub issue work when the user explicitly asks to start or resume an issue, inspect workflow status or next work, prepare a pull request, or clean completed work. Ordinary issue discussion, issue creation, code review, direct closure, and merging are outside this skill.
---

# GitHub issue workflow

Manage the mechanics around existing GitHub issues. GitHub is the only issue
tracker this skill supports. Issue creation, product planning, implementation,
PR review, and merging remain separate user-directed work.

Use `gh` directly for read-only GitHub inspection. Keep ordinary status bounded:
do not recursively fetch every descendant, search the full pull-request
inventory, or inspect local worktrees unless the user requests local work
status.

The current implementation supports read-only `status`. It does not support
`start`, `finish`, or `clean`. Explain this boundary. Do not approximate a
mutating command with shell calls.

<important if="the user naturally phrases an action instead of explicitly invoking gh-issue">

Map only clear start, resume, status, finish, prepare-PR, clean, or clean-up
intent to this skill. A bare issue reference or a request to discuss, create,
review, close, prioritize, or merge an issue is outside this workflow.

For a natural-language request that would mutate state, show the resolved issue
and planned mutations, then request confirmation. An explicit `gh-issue`
command is already authorization for that command. An inferred issue always
requires confirmation before mutation.

</important>

<important if="the user asks for issue status or what to work on next">

Resolve the repository from explicit `OWNER/REPO` input or from the current
checkout. An explicit issue number does not require confirmation. Then run the
query in `references/status.graphql` with one `gh` call:

```text
gh api graphql -F owner=OWNER -F name=REPOSITORY -F number=NUMBER -F query=@<skill-directory>/references/status.graphql
```

If no issue number is supplied, list at most ten recent open issues authored by
the user and ten assigned to the user with `gh issue list`. Deduplicate them,
then present the candidates with the harness's native selection control. Use a
short numbered question when no native control exists. Accept a manually
entered issue number. Do not choose for the user.

Classify an issue with children as compound and an issue without children as
standalone. Treat only open blockers as active. For a compound issue, recommend
the first open direct child with no active blocker. If that child is compound,
repeat the same query for that child only until the recommendation reaches a
standalone issue. Do not inspect sibling descendants.

Render the issue state, classification, parent, direct-child progress, active
blockers, recommendation, recommendation reason, and next mechanical action.
Status is read-only. A recommendation is never permission to start that issue.
If GitHub returns no issue or truncates a relationship, report that limit. Do
not invent a complete status or recommendation from partial data.

</important>

<important if="the user explicitly asks for local implementation status, branches, worktrees, a pull request, or checks">

After the bounded GitHub status query, inspect only the requested local or PR
evidence. Match issue-shaped branch names and explicit PR issue references.
Do not list or analyze unrelated pull requests or worktrees.

</important>

<important if="the user asks to start or resume an issue">

Resolve and display the issue and its ancestor hierarchy. If the skill infers
an issue, confirm the issue before a state change. Create only the missing
ancestor integration path and the requested issue worktree. Then stop. Do not
begin implementation.

This command is unavailable until its deterministic script is implemented.

</important>

<important if="the user asks to finish an issue or prepare its PR">

Review the change set, run required checks, commit intended changes, push the
branch, and create or update the correctly targeted ready-for-review PR. Return
the PR unmerged. A compound issue cannot finish while a direct child remains
open or has an unmerged PR targeting its integration branch.

This command is unavailable until its deterministic script is implemented.

</important>

<important if="the user asks to clean an issue">

Confirm that the top compound effort reached the stable branch. Show every
local and remote worktree or branch that the command will remove. Request
confirmation immediately before deletion. Preserve dirty, protected, active,
open-PR, or unmerged state. `--local-only` preserves remote branches.

This command is unavailable until its deterministic script is implemented.

</important>

<important if="issue identity, hierarchy, ownership, changes, branches, or validation are ambiguous">

If the evidence conflicts, show the conflict. Wait for the user to resolve the
conflict before any related change. Prefer native GitHub relationships. When a
native relationship is absent, explicit `Parent:` or `Blocked by:` fields and
issue references in checklists or under Children, Sub-issues, Tasks, or Work
items headings in the focused issue body are valid evidence. Ordinary issue
references are not hierarchy evidence. Do not search other issue bodies during
ordinary status.

</important>

<important if="the workflow recommends another issue">

Prefer an already-started unfinished standalone issue. Otherwise recommend the
first open, unblocked standalone issue in GitHub hierarchy order, descending
through compound issues as needed. Explain the evidence and wait for the user
to choose or override it.

</important>
