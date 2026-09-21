---
name: gh-issue
description: Manage existing GitHub issue work when the user explicitly asks to start or resume an issue, inspect workflow status or next work, prepare a pull request, or clean completed work. Ordinary issue discussion, issue creation, code review, direct closure, and merging are outside this skill.
---

# GitHub issue workflow

Manage the mechanics around existing GitHub issues. GitHub is the only issue
tracker this skill supports. Issue creation, product planning, implementation,
PR review, and merging remain separate user-directed work.

Use `gh`, `git`, and the selected worktree manager directly. Do not create a
helper program for this workflow. Keep each path bounded: do not recursively
fetch every descendant, search the full pull-request inventory, or inspect
unrelated branches and worktrees.

The current implementation supports `status` and `start`. It does not support
`finish` or `clean`. Explain this boundary. Do not approximate an unavailable
command with shell calls.

<important if="the user naturally phrases an action instead of explicitly invoking gh-issue">

Map only clear start, resume, status, finish, prepare-PR, clean, or clean-up
intent to this skill. A bare issue reference or a request to discuss, create,
review, close, prioritize, or merge an issue is outside this workflow.

Treat `start issue NUMBER`, `issue start NUMBER`, `GitHub issue NUMBER start`,
and equivalent unambiguous imperatives as explicit authorization. An explicit
`gh-issue` command is also authorization. If you must infer the issue or
intended action, show the resolved issue and dry-run plan. Then request
confirmation before mutation.

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
an issue, confirm the issue before a state change. Then create only the branch
and worktree required by the repository's policy. Stop before implementation.

For an explicit issue, make one GitHub request with
`references/start.graphql`:

```text
gh api graphql -F owner=OWNER -F name=REPOSITORY -F number=NUMBER -F query=@<skill-directory>/references/start.graphql
```

In the same tool call, read `~/.config/agent-skills/config.json` when it exists.
The canonical settings are top-level. Match `repositories["OWNER/REPOSITORY"]`,
then match an `efforts` key to the requested issue or any returned ancestor.
The nearest matching effort wins. Explicit user and loaded repository
instructions take precedence. Do not list or reread the skill files.

An effort's fixed `integrationBranch` replaces the generic ancestor branch
layout. Use its `taskBranchTemplate` and `worktreeTemplate`. If no effort policy
matches, reuse exact existing issue work when available. Show the generic plan
and ask the user before you create branches for an unconfigured effort.
Do not inspect sibling issues, pull requests, or unrelated branches to infer a
policy.

Reject a missing or closed issue, a closed parent, or a truncated hierarchy.
Then make one batched local inspection. Resolve the primary checkout from Git's
common directory. Inspect `git worktree list --porcelain`, only branch refs that
match the issue number or configured policy, and the Supacode repository list.
Use the returned JSON directly. Do not add a separate parsing command.

If the issue already has a matching worktree, report it and stop. Do not inspect
its commits, pull requests, checks, or relation to the base branch. Those checks
belong to local implementation status and finish.

If worktree creation remains necessary, fetch once. Stop if the destination
belongs to another branch or the required base worktree is dirty. Use the
configured manager. In `auto` mode, prefer Supacode when the primary repository
is registered. Create a new Supacode worktree with:

```text
supacode repo worktree-new -r REPOSITORY_ID --branch BRANCH --base BASE --location REPOSITORY_WORKTREE_ROOT --name WORKTREE_NAME --background
```

Capture the returned worktree ID. Use `git worktree add` only when the selected
manager is `git` or Supacode is unavailable in `auto` mode. Push each new
integration branch to `origin`. Leave the task branch local until finish.
Verify the checked-out branch, report the worktree path, and stop.

For an existing local branch, omit `--base` from the Supacode command. For an
existing remote branch, use `--base origin/BRANCH --upstream origin/BRANCH`.
The native Git equivalents are:

```text
git -C PRIMARY worktree add -b BRANCH DESTINATION BASE
git -C PRIMARY worktree add DESTINATION BRANCH
git -C PRIMARY worktree add -b BRANCH --track DESTINATION origin/BRANCH
```

Before mutation, use no more than the one hierarchy query and one batched local
inspection. If they do not resolve the base branch, branch name, destination,
or manager, show the unresolved value and ask one question. Do not continue
investigating.

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
