---
name: gh-issue
description: Manage existing GitHub issue work when the user explicitly asks to start or resume an issue, inspect workflow status or next work, prepare a pull request, or clean completed work. Ordinary issue discussion, issue creation, code review, direct closure, and merging are outside this skill.
---

# GitHub issue workflow

Manage the mechanics around existing GitHub issues. GitHub is the only issue
tracker this skill supports. Issue creation, product planning, implementation,
PR review, and merging remain separate user-directed work.

Use the dependency-free helper at `scripts/gh-issue.mjs` for deterministic
inspection and mutations. Never reproduce its Git, GitHub, hierarchy, or
worktree logic ad hoc.

The current implementation supports read-only `status`. The scripts do not
support `start`, `finish`, or `clean`. Explain this boundary. Do not approximate
a mutating command with shell calls.

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

Run:

```text
node <skill-directory>/scripts/gh-issue.mjs status [issue-number] --json
```

If it returns `selection_required`, present its candidates with the harness's
native selection control. Use a short numbered question when no native control
exists. Accept a manually entered issue number. Do not choose for the user.

Render the returned issue, classification, hierarchy, worktrees, branches, PRs,
checks, blockers, conflicts, recommendation, recommendation reason, and next
mechanical action. Status is read-only. A recommendation is never permission to
start that issue.

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
conflict before any related change. Native GitHub relationships, explicit `Parent:` or `Blocked
by:` fields, and issue references in checklists or under Children, Sub-issues,
Tasks, or Work items headings are valid evidence. Ordinary issue references are
not hierarchy evidence.

</important>

<important if="the workflow recommends another issue">

Prefer an already-started unfinished standalone issue. Otherwise recommend the
first open, unblocked standalone issue in GitHub hierarchy order, descending
through compound issues as needed. Explain the evidence and wait for the user
to choose or override it.

</important>
