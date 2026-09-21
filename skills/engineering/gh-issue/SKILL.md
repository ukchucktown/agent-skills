---
name: gh-issue
description: Manage existing GitHub issue work when the user explicitly asks to start or resume an issue, inspect workflow status or next work, prepare a pull request, or clean completed work. Ordinary issue discussion, issue creation, code review, direct closure, and merging are outside this skill.
---

# GitHub issue workflow

Manage the mechanics around existing GitHub issues. GitHub is the only issue
tracker this skill supports. Issue creation, product planning, implementation,
PR review, and merging remain separate user-directed work.

Use the checked-in commands for status and finish. Use the query wrapper for
start. Use `gh`, `git`, and the selected worktree manager directly when start
requires GitHub or local setup. Keep each path bounded: do not recursively
fetch every descendant, search the full pull-request inventory, or inspect
unrelated branches and worktrees.

The current implementation supports `status`, `start`, and `finish`. It does
not support `clean`. Explain this boundary. Do not approximate an unavailable
command with shell calls.

<important if="the user naturally phrases an action instead of explicitly invoking gh-issue">

Map only clear start, resume, status, finish, prepare-PR, clean, or clean-up
intent to this skill. A bare issue reference or a request to discuss, create,
review, close, prioritize, or merge an issue is outside this workflow.

Treat `start issue NUMBER`, `finish issue NUMBER`, `issue start NUMBER`, `issue
finish NUMBER`, `GitHub issue NUMBER start`, `GitHub issue NUMBER finish`, and
equivalent unambiguous imperatives as explicit authorization. An explicit
`gh-issue` command is also authorization. If you must infer the issue or
intended action, show the resolved issue and dry-run plan. Then request
confirmation before mutation.

</important>

<important if="the user asks for issue status or what to work on next">

Resolve the repository from explicit `OWNER/REPO` input or from the current
checkout. An explicit issue number does not require confirmation. Run the
status command directly without opening, listing, or reconstructing it:

```text
<skill-directory>/scripts/status.sh OWNER/REPOSITORY NUMBER
```

Pass `.` instead of `OWNER/REPOSITORY` when the current checkout is the target.
The command performs the bounded GitHub reads, applies the optional Project
configuration, follows only the recommended compound path, and renders the
complete result. Relay its output. Do not add a parsing or discovery command.

If no issue number is supplied, list at most ten recent open issues authored by
the user and ten assigned to the user with `gh issue list`. Deduplicate them,
then present the candidates with the harness's native selection control. Use a
short numbered question when no native control exists. Accept a manually
entered issue number. Do not choose for the user.

Status is read-only. A recommendation is never permission to start that issue.
Report command errors directly. Do not reconstruct a result after an error.

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

For an explicit issue, run the query wrapper without opening, listing, or
reconstructing it:

```text
<skill-directory>/scripts/query.sh start OWNER/REPOSITORY NUMBER
```

Pass `.` instead of `OWNER/REPOSITORY` when the current checkout is the target.
The wrapper makes one `gh api graphql` call and returns its JSON. Use that JSON
directly. Do not add a parsing command.

When `repositories[OWNER/REPOSITORY].projectStatus.enabled` is `true`, run
`query.sh project-status` for the same issue in this initial tool call. Also
check that GitHub CLI authentication has `read:project` and `project` scopes.
The optional object uses `field` and `startOption`, with `Status` and `In
Progress` as defaults. Repositories without the enabled setting make no Project
request. A missing scope, truncated Project result, or missing or duplicated
configured field or option stops start before any mutation. Report one clear
corrective action.

Run the wrapper and the compact read-only local inspection in one tool call.
Do not resolve the origin in a separate call. In that same call, read
`~/.config/agent-skills/config.json` when it exists, resolve the primary checkout
from Git's common directory, and output:

- The compact `git worktree list` output. Omit `--porcelain` because its HEAD
  and lock metadata are not start evidence.
- Local and remote refs that contain the bounded issue number.
- The primary checkout's current branch and short status.
- Only the matching repository ID from `supacode repo list` when Supacode is the
  selected or automatic manager.

Do not emit unrelated refs, Supacode repository IDs, or per-worktree metadata.
Keep the compact worktree branches because sibling patterns can identify a
shared integration branch.

Shared configuration settings are top-level. Project settings live under the
exact repository entry. Apply configured manager, root, or branch templates.
Explicit user and loaded repository instructions take precedence. Do not list
or reread the skill files.

Reject a missing or closed issue, a closed parent, or a truncated hierarchy.
Also reject a truncated linked-branch result. Use only the data from the
combined query and local inspection. Do not add a separate parsing or discovery
command.

Treat a non-null linked branch or a unique local branch or worktree with a
bounded issue marker such as `-83-` as existing issue work, regardless of its
naming prefix. If the issue already has a matching worktree, update stale
configured Project status, report the worktree, and stop. If the issue has one
linked remote branch without a worktree, an explicit start reports that the
issue is already started and stops. An explicit resume attaches that branch
through the configured manager. Do not create a second branch. Do not inspect
commits, pull requests, checks, or relation to the base branch. Those checks
belong to local implementation status and finish.

When a configured Project already has its start value but no linked or local
issue branch exists, report possible work by another contributor and stop. Do
not create duplicate work from local absence alone.

For missing issue work, prefer an explicit configured or repository policy.
Otherwise, infer a shared integration branch only when one candidate is
supported by both the returned hierarchy and local evidence. Strong evidence
includes a non-default current branch whose name matches an issue or ancestor
label, or a repeated sibling branch prefix based on the direct parent's returned
child numbers. Existing evidence replaces the generic ancestor branch layout.
Do not inspect pull requests, issue bodies, or unrelated branches to strengthen
an inference.

If the evidence identifies one shared integration branch and one task prefix,
show them and proceed. If it identifies several conflicting candidates, show
them and ask one question. For an explicit start with no existing pattern, show
the generic per-compound integration plan and create it without another
confirmation.

If configured Project items need an update, make those edits first in the
mutation call. Update the focused issue and every ancestor in its start plan.
Use each exact Project match returned by the optional query:

```text
gh project item-edit PROJECT_NUMBER --owner PROJECT_OWNER --url ISSUE_URL --field FIELD --value START_OPTION
```

Stop on an update failure before branch creation.

Create every missing issue branch as a GitHub-linked remote branch from its
resolved base. This applies to compound integration branches and standalone task
branches:

```text
gh issue develop NUMBER --repo OWNER/REPOSITORY --base BASE --name BRANCH
```

Then fetch once and create the worktree from `origin/BRANCH`. Stop if the
destination belongs to another branch or a required base worktree is dirty. Use
the configured manager. In `auto` mode, prefer Supacode when the primary
repository is registered. Create a Supacode worktree with:

```text
supacode repo worktree-new -r REPOSITORY_ID --branch BRANCH --base origin/BRANCH --upstream origin/BRANCH --location REPOSITORY_WORKTREE_ROOT --name WORKTREE_NAME --background
```

Capture the returned worktree ID. Use `git worktree add -b BRANCH --track
DESTINATION origin/BRANCH` only when the selected manager is `git` or Supacode
is unavailable in `auto` mode. Every new task and integration branch is remote
and linked from start. Verify the checked-out branch, report the linked branch
and worktree path, and stop.

For an existing local branch, omit `--base` from the Supacode command. For an
existing remote branch, use `--base origin/BRANCH --upstream origin/BRANCH`.
The native Git equivalents are:

```text
git -C PRIMARY worktree add DESTINATION BRANCH
git -C PRIMARY worktree add -b BRANCH --track DESTINATION origin/BRANCH
```

Treat this as a round-trip budget. Resolve issue work in one tool call that
combines the query and local inspection. Any required Project synchronization or
new work may use one additional call that batches Project updates, linked-branch
creation, fetch, worktree creation, and verification. If the first call does not
resolve the base branch, branch name, destination, or manager, show the
unresolved value and ask one question. Do not investigate or spend extra calls
to improve confidence.

</important>

<important if="the user asks to finish an issue or prepare its PR">

Treat an explicit issue number as authorization to review, validate, commit,
push, prepare its PR, or close verified no-change work as completed. Finish
returns a ready-for-review PR unmerged when the branch contains changes.

Run the finish command without opening, listing, or reconstructing it:

```text
<skill-directory>/scripts/finish.sh OWNER/REPOSITORY NUMBER
```

Pass `.` instead of `OWNER/REPOSITORY` when the current checkout is the target.
The command resolves the worktree, branch, base, exact-head pull request,
direct children, worktree state, and merge-base diff. It closes verified
no-change work as completed. Relay a completed or blocked result and stop.
If the command cannot resolve a parent base, ask one question and rerun it with
the reported `--base BRANCH` option.

When the command reports changed paths, use its worktree, branch, base, and
pull-request values for the rest of finish. Do not repeat its inspection.

Review every changed path and the complete diff in the selected worktree.
Separate intended issue work from unrelated changes. Use the validation commands
named by loaded repository instructions or its immediately visible root task
configuration. If the intended changes or required validation are ambiguous,
ask one question and stop. Run the required checks and stop on failure.

Commit only the intended paths. Use a scoped message that includes the issue
number, then push the selected branch with its upstream.

Reuse the pull request from the command output. Create a ready-for-review pull
request when none exists. Set the reported base, summarize the delivered
behavior and validation, and end the body with `Closes #NUMBER`. Update an
existing pull request when those values differ. Mark it ready when it is a
draft. Never merge the pull request.

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

Prefer an unfinished standalone issue with matching linked or local work.
Project status without branch evidence can represent another contributor's
work, so exclude that issue from recommendations. Otherwise recommend the first
open, unblocked standalone issue in GitHub hierarchy order, descending through
compound issues as needed. Explain the evidence and wait for the user to choose
or override it.

</important>
