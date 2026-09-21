---
name: gh-issue
description: Manage existing GitHub issue work when the user explicitly asks to start or resume an issue, inspect workflow status or next work, prepare a pull request, or clean completed work. Ordinary issue discussion, issue creation, code review, direct closure, and merging are outside this skill.
---

# GitHub issue workflow

Manage the mechanics around existing GitHub issues. GitHub is the only issue
tracker this skill supports. Issue creation, product planning, implementation,
PR review, and merging remain separate user-directed work.

Use the checked-in query wrapper for GitHub reads. Use `git` and the selected
worktree manager directly when start requires local setup. Keep each path
bounded: do not recursively fetch every descendant, search the full pull-request
inventory, or inspect unrelated branches and worktrees.

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
wrapper directly without opening, listing, or reconstructing it:

```text
<skill-directory>/scripts/query.sh status OWNER/REPOSITORY NUMBER
```

Pass `.` instead of `OWNER/REPOSITORY` when the current checkout is the target.
The wrapper makes one `gh api graphql` call and returns its JSON. Use that JSON
directly. Do not add a parsing command.

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

The canonical configuration settings are top-level. Apply configured manager,
root, or branch templates. Explicit user and loaded repository instructions
take precedence. Do not list or reread the skill files.

Reject a missing or closed issue, a closed parent, or a truncated hierarchy.
Use only the data from the combined query and local inspection. Do not add a
separate parsing or discovery command.

Treat a unique branch or worktree with a bounded issue marker such as `-83-` as
existing issue work, regardless of its naming prefix. If the issue already has
a matching worktree, report it and stop. Do not inspect its commits, pull
requests, checks, or relation to the base branch. Those checks belong to local
implementation status and finish.

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

Treat this as a round-trip budget. Resolve existing issue work in one tool call
that combines the query and local inspection. New work may use one additional
call that batches fetch, creation, any integration-branch push, and verification.
If the first call does not resolve the base branch, branch name, destination, or
manager, show the unresolved value and ask one question. Do not investigate or
spend extra calls to improve confidence.

</important>

<important if="the user asks to finish an issue or prepare its PR">

Treat an explicit issue number as authorization to review, validate, commit,
push, and prepare its PR. Finish always returns a ready-for-review PR unmerged.

Run the query wrapper without opening, listing, or reconstructing it:

```text
<skill-directory>/scripts/query.sh finish OWNER/REPOSITORY NUMBER
```

Pass `.` instead of `OWNER/REPOSITORY` when the current checkout is the target.
The wrapper makes one `gh api graphql` call and returns its JSON. Use that JSON
directly. Do not add a parsing command.

Run the wrapper and bounded local inspection in one tool call. In that call,
read the optional global configuration and resolve the primary checkout from
Git's common directory. Output the current branch, short status, worktree list,
and local and remote refs that contain the bounded issue number.

Prefer the current worktree when its branch has that issue marker. Otherwise,
use one matching worktree and branch. Ask one question when the match is missing
or not unique. End the inquiry there.

Reject a missing or closed issue, a truncated hierarchy, or a direct-child
result whose node count differs from `totalCount`. A compound issue also stops
when a direct child is open.

Use one batched read-only tool call after you resolve the branch. Query pull
requests for that exact head branch. For a compound issue, also query open pull
requests that target its integration branch. Any result identifies unfinished
child delivery work and stops finish. Limit each result to two. Reuse these
results through the rest of finish.

```text
gh pr list --repo OWNER/REPOSITORY --head BRANCH --state all --limit 2 --json number,title,state,isDraft,url,baseRefName,headRefName
gh pr list --repo OWNER/REPOSITORY --base BRANCH --state open --limit 2 --json number,title,state,isDraft,url,baseRefName,headRefName
```

Run the second command only for a compound issue.

Resolve the PR base from the first available source:

1. An existing PR for the exact head branch.
2. Explicit user or loaded repository instructions.
3. One integration branch supported by the hierarchy and bounded local
   evidence.
4. The GitHub default branch when the issue has no parent.

Collect unresolved values into one question and stop. Do not inspect unrelated
branches or pull requests.

Review every changed path and the complete diff in the selected worktree.
Separate intended issue work from unrelated changes. Use the validation commands
named by loaded repository instructions or its immediately visible root task
configuration. If the intended changes or required validation are ambiguous,
ask one question and stop. Run the required checks and stop on failure.

Commit only the intended paths. Use a scoped message that includes the issue
number, then push the selected branch with its upstream.

Reuse the single open PR returned by the exact-head lookup. A closed unmerged PR
or multiple matches is ambiguous. A merged PR means that the work is already
delivered. Report it and stop. Otherwise, create a ready-for-review PR. Set the
resolved base, summarize the delivered behavior and validation, and end the body
with `Closes #NUMBER`. Update an existing PR when those values differ. Mark it
ready when it is a draft.

Treat finish as a round-trip budget. Use the initial combined query and local
inspection, one batched read for the exact PR and any compound base lookup, the
repository's validation, and the required mutations. Ambiguity produces one
question and no further tool calls. Never merge the PR.

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
