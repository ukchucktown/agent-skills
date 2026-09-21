---
name: gh-issue
description: Manage existing GitHub issue work when the user explicitly asks to start or resume an issue, inspect workflow status or next work, prepare a pull request, clean completed or residual work, or cancel abandoned work. Ordinary issue discussion, issue creation, code review, direct closure, and merging are outside this skill.
---

# GitHub issue workflow

Manage the mechanics around existing GitHub issues. GitHub is the only issue
tracker this skill supports. Issue creation, product planning, implementation,
PR review, and merging remain separate user-directed work.

Use the checked-in commands for status, Project synchronization, and finish.
Use the query wrapper for the remaining start reads. Use `gh`, `git`, and the
selected worktree manager directly when start requires GitHub or local setup.
Keep each path bounded: do not recursively fetch every descendant, search the
full pull-request inventory, or inspect unrelated branches and worktrees.

The current implementation supports `status`, `start`, `finish`, `clean`, and
`cancel`.

Cleanup and cancellation commands emit each discovery result and detailed plan
as one buffered block. Put that complete output in one fenced `text` code block
in the user-facing response. Preserve the text verbatim. Do not convert branch
names to Markdown bullets, inline code, or another list. This format keeps the
output in one copyable region and avoids per-branch Markdown pills.

A confirmed command prints a compact count summary before it applies the
unchanged plan. Relay only that summary and the final result as normal prose.
Do not repeat the detailed branch and worktree lists. If a confirmation token
is stale, put the refreshed detailed plan in one fenced `text` code block.

<important if="the user naturally phrases an action instead of explicitly invoking gh-issue">

Map only clear start, resume, status, finish, prepare-PR, clean, clean-up,
cancel, or abandon intent to this skill. A bare issue reference or a request to
discuss, create, review, close, prioritize, or merge an issue is outside this
workflow.

Treat `start issue NUMBER`, `finish issue NUMBER`, `issue start NUMBER`, `issue
finish NUMBER`, `GitHub issue NUMBER start`, `GitHub issue NUMBER finish`, and
equivalent unambiguous imperatives as explicit authorization. An explicit
`gh-issue` command is also authorization. If you must infer the issue or
intended action, show the resolved issue and dry-run plan. Then request
confirmation before mutation.

</important>

<important if="the user asks to cancel or abandon an issue effort">

Treat only an explicit cancel or abandon request as authorization to plan
cancellation. Run the cancel command from the repository's primary checkout on
its stable branch:

```text
<skill-directory>/scripts/cancel.sh OWNER/REPOSITORY NUMBER
```

Pass `.` instead of `OWNER/REPOSITORY` when the current checkout is the target.
Pass `--local-only` before the repository only when the user explicitly wants
to preserve remote branches. The command resolves the top-level effort and
prints one combined plan. It lists open issues that will close as `Not planned`,
open pull requests that will close without merging, issue worktrees and
branches that will be removed, warnings, and preserved artifacts. Planning is
read-only and creates no saved plan file.

Cancellation is allowed to discard unmerged commits, divergent local and
remote tips, uncommitted changes, and worktrees active in Supacode. It never
removes the stable checkout, a protected branch, an unrelated branch, an
unavailable worktree, or a branch used by more than one worktree. Relay the
plan without reconstructing it.

Request one confirmation immediately before applying the plan. After
confirmation, pass the exact displayed token:

```text
<skill-directory>/scripts/cancel.sh --confirm TOKEN OWNER/REPOSITORY NUMBER
```

Keep `--local-only` on the confirmed command when it appeared on the plan. If
the command rejects a stale token, relay the new plan and request confirmation
again. Do not close, delete, or preserve individual artifacts with separate
Git, GitHub, filesystem, or Supacode commands.

</important>

<important if="the user asks to clean repository artifacts without an issue number">

Resolve the target from an explicit repository first. Otherwise use the
repository containing the user's current workspace or working directory. Never
substitute the skill's source repository or the repository used by earlier
work. Run discovery from that repository's primary checkout on its stable
branch and verify that the reported `Repository` is the intended target.

Run repository cleanup discovery from the primary checkout on its stable
branch:

```text
<skill-directory>/scripts/clean.sh OWNER/REPOSITORY
```

Pass `.` when the current checkout is the target. The command returns numbered
groups for non-stable local and remote branches, including branches whose
worktrees are already gone. It groups matching local and remote branches by
name, includes an attached worktree when present, and separates selectable
groups from blocked groups. Discovery is read-only. Relay the complete result
verbatim in one fenced `text` code block.

The user-facing text block must contain the target repository, every selectable
number with its branch name, and every blocked branch with its reason. Tool
output does not satisfy this requirement because the harness may collapse or
hide it. Do not add branches from another search, omit command fields, or
replace the result with counts or a representative sample.

Ask the user to select one or more selectable groups. Use the harness's native
control only when it supports simultaneous selection of every candidate and an
explicit Select all action. A single-choice picker does not qualify. Otherwise,
show the numbered list once and accept `all`, comma-separated numbers, ranges,
or exact branch names in one reply. Do not require the user to retype branch
names when numbered candidates are available. Selection is permission to build
the plan, not permission to delete.

For `all`, build one combined plan with `--all`. For a subset, resolve the
chosen numbers or ranges from the displayed list and repeat `--select` for the
corresponding branches:

```text
<skill-directory>/scripts/clean.sh --all OWNER/REPOSITORY
<skill-directory>/scripts/clean.sh --select BRANCH [--select BRANCH...] OWNER/REPOSITORY
```

Pass `--local-only` before the selections only when the user wants to preserve
remote branches. Relay the plan without reconstructing it. Ordinary repository
cleanup blocks dirty or Supacode-active worktrees, divergent local and remote
tips, and branches whose tip is not contained in the stable branch. It also
keeps the primary checkout, default and protected branches, branches with open
pull requests, unavailable worktrees, branches shared by multiple worktrees,
and every unselected group.

Treat force cleanup as separate explicit intent. Never infer it from `all` or
from confirmation of an ordinary cleanup plan. Only when the user explicitly
asks to force cleanup may you rerun discovery and planning with `--force`.
Force makes dirty, active, divergent, and unmerged groups selectable and shows
those risks as warnings. It does not override the other protections.

Request one confirmation immediately before deletion. Apply the same selection
and mode with the exact displayed token:

```text
<skill-directory>/scripts/clean.sh --all --confirm TOKEN OWNER/REPOSITORY
<skill-directory>/scripts/clean.sh --select BRANCH [--select BRANCH...] --confirm TOKEN OWNER/REPOSITORY
```

Keep `--force` on planning and confirmation commands only when the user
explicitly requested force cleanup.

If the command rejects a stale token, relay the new plan and request
confirmation again. Repository cleanup changes no issue or pull-request state.
Use issue cancellation when the requested action includes closing work as `Not
planned`.

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

Run the wrapper and the compact read-only local inspection in one tool call.
Do not resolve the origin in a separate call. In that same call, read
the effective Project settings with the command below, resolve the primary
checkout from Git's common directory, and output:

```text
<skill-directory>/scripts/project-config.sh OWNER/REPOSITORY
```

- The compact `git worktree list` output. Omit `--porcelain` because its HEAD
  and lock metadata are not start evidence.
- Local and remote refs that contain the bounded issue number.
- The primary checkout's current branch and short status.
- Only the matching repository ID from `supacode repo list` when Supacode is the
  selected or automatic manager.

Do not emit unrelated refs, Supacode repository IDs, or per-worktree metadata.
Keep the compact worktree branches because sibling patterns can identify a
shared integration branch.

Shared configuration settings are top-level. A top-level `projectStatus`
applies only when its owner matches the repository owner. An exact repository
entry can disable or override it. Apply configured manager, root, or branch
templates. Explicit user and loaded repository instructions take precedence.
Do not list or reread the skill files.

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

In the mutation call, synchronize the configured Project before branch
creation:

```text
<skill-directory>/scripts/project-start.sh OWNER/REPOSITORY NUMBER
```

The command validates Project access and configuration, adds missing items to a
configured target Project, and updates the focused issue and its open ancestors.
Stop on an error before branch creation. When it reports that the focused issue
already had the start value and no linked or local issue branch exists, report
possible work by another contributor and stop. Do not create duplicate work
from local absence alone.

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
combines the query, effective Project configuration, and local inspection. Any
required Project synchronization or new work may use one additional call that
batches Project updates, linked-branch creation, fetch, worktree creation, and
verification. If the first call does not resolve the base branch, branch name,
destination, or manager, show the unresolved value and ask one question. Do not
investigate or spend extra calls to improve confidence.

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

Run the clean command from the repository's primary checkout on its stable
branch:

```text
<skill-directory>/scripts/clean.sh OWNER/REPOSITORY NUMBER
```

Pass `.` instead of `OWNER/REPOSITORY` when the current checkout is the target.
Pass `--local-only` before the repository when the user wants to preserve
remote branches. The command resolves the top-level effort, verifies its issue
tree and branch state, and prints the complete cleanup plan. Planning is
read-only and creates no saved plan file.

Relay the plan without reconstructing it. The command preserves dirty or
unavailable worktrees, the active checkout, protected branches, branches with
open pull requests, divergent local and remote tips, and work that cannot be
verified in the stable branch. Stop when nothing is eligible.

Request confirmation immediately before deletion. After confirmation, apply
only the displayed plan with its exact token:

```text
<skill-directory>/scripts/clean.sh --confirm TOKEN OWNER/REPOSITORY NUMBER
```

Keep `--local-only` on the confirmed command when it appeared on the plan. If
the command rejects a stale token, relay the new plan and request confirmation
again. Do not delete a preserved item manually and do not approximate cleanup
with separate Git, GitHub, filesystem, or Supacode commands.

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
