---
name: gh-issue
description: Manage existing GitHub issue work when the user explicitly asks to start or resume an issue, inspect workflow status or next work, prepare a pull request, clean completed or residual work, or cancel abandoned work. Ordinary issue discussion, issue creation, code review, direct closure, and merging are outside this skill.
---

# GitHub issue workflow

Manage the mechanics around existing GitHub issues. GitHub is the only issue
tracker this skill supports. Issue creation, product planning, implementation,
PR review, and merging remain separate user-directed work.

Use the checked-in commands for each workflow. Do not reconstruct their reads,
plans, Git operations, GitHub operations, or worktree-manager operations. Keep
each path bounded: do not recursively fetch every descendant, search the full
pull-request inventory, or inspect unrelated branches and worktrees.

The current implementation supports `status`, `start`, `resume`, `finish`,
`clean`, and `cancel`.

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
open pull requests that will close with no merge, issue worktrees and branches
that the command will remove, warnings, and preserved artifacts. Planning is
read-only and creates no saved plan file.

Cancellation is allowed to discard unmerged commits, divergent local and
remote tips, uncommitted changes, and worktrees active in Supacode. It never
removes the stable checkout, a protected branch, an unrelated branch, an
unavailable worktree, or a branch used by more than one worktree. Relay the
command's plan. Do not reconstruct it.

Request one confirmation immediately before you apply the plan. After
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
groups from blocked groups. The rendered discovery and plan show each branch
once, with its worktree, references, warnings, and planned actions nested under
that branch. Discovery is read-only. Relay the complete result verbatim in one
fenced `text` code block.

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
remote branches. Relay the command's plan. Do not reconstruct it. Ordinary repository
cleanup blocks dirty or Supacode-active worktrees and divergent local and
remote tips. It accepts a branch tip under either condition:

- The stable branch contains the tip.
- A merged pull request records the tip as its exact head.

It also keeps the primary checkout, default and protected branches, branches
with open pull requests, unavailable worktrees, branches shared by multiple
worktrees, and every unselected group.

Treat force cleanup as separate explicit intent. Never infer it from `all` or
from confirmation of an ordinary cleanup plan. Only when the user explicitly
asks to force cleanup may you rerun discovery and planning with `--force`.
Force makes dirty, active, divergent, and unmerged groups selectable and shows
those risks as warnings. It also removes a selected Git worktree if the
worktree acquires a lock after the command creates the plan. It does not
override the other protections.

Request one confirmation immediately before deletion. Apply the same selection
and mode with the exact displayed token:

```text
<skill-directory>/scripts/clean.sh --all --confirm TOKEN OWNER/REPOSITORY
<skill-directory>/scripts/clean.sh --select BRANCH [--select BRANCH...] --confirm TOKEN OWNER/REPOSITORY
```

Keep `--force` on commands that plan and confirm only when the user explicitly
requested force cleanup.

If the command rejects a stale token, relay the new plan and request
confirmation again. If application fails after mutation starts, relay the
partial-completion counts and rerun discovery before another plan. Repository
cleanup changes no issue or pull-request state. Use issue cancellation when
the requested action includes closing work as `Not planned`.

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

If the skill inferred the issue, confirm the issue before a state change. For
an explicit issue, run one command from a checkout of the target repository:

```text
<skill-directory>/scripts/start.sh start OWNER/REPOSITORY NUMBER
<skill-directory>/scripts/start.sh resume OWNER/REPOSITORY NUMBER
```

Pass `.` instead of `OWNER/REPOSITORY` when the current checkout is the target.
The command resolves and validates the hierarchy, existing work, effective
configuration, branch layout, destination, and worktree manager. It
checks ancestor branches for missing commits and applies the optional repository
task base from [the start configuration](references/start-config.md). It assigns
the authenticated user when the issue has no assignee. It preserves and reports
existing assignees. It synchronizes configured Project status and creates or
attaches the GitHub-linked branch and worktree. It verifies the checked-out
branch and returns a compact result. Relay that result and stop before implementation.

Do not run separate `query.sh`, `project-config.sh`, `project-start.sh`, `gh`,
`git`, or worktree-manager commands for start or resume. Do not delegate the
command to another agent.

A conflict returns one JSON object with `status: needs_input`, a `field`, one
`question`, and bounded `candidates`. Ask that exact question. Then rerun the
same command once with the matching option:

```text
--branch BRANCH
--base BRANCH
--destination PATH
--manager auto|supacode|git
```

Do not investigate beyond the command result. Other nonzero results are
blocked outcomes. Relay the command's result. Do not reconstruct the workflow.

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
direct children, worktree state, and merge-base diff. It fetches the remote base
branch for the comparison. It uses a local base only when the remote branch
does not exist. A remote lookup or fetch failure blocks finish. It closes verified
no-change work as completed. Relay a completed or blocked result and stop.
If the command cannot resolve a parent base, ask one question and rerun it with
the reported `--base BRANCH` option.

When the command reports changed paths, use its worktree, branch, base, and
pull-request values for the rest of finish. Do not repeat its inspection.

The result separates committed paths from uncommitted paths. Uncommitted paths
use Git status codes and include staged, unstaged, and untracked files.
Review every changed path and the complete diff in the selected worktree.
Review the staged and unstaged diffs. Read untracked files before any commit.
If the command reports unresolved conflicts, resolve those conflicts before
another finish attempt.
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

Relay the command's plan. Do not reconstruct it. The command preserves dirty or
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
