# `gh-issue`

`gh-issue` manages the mechanics around existing GitHub issues. It gives Codex,
Claude Code, and GitHub Copilot the same workflow for issue status, worktree
creation, pull-request preparation, cleanup, and cancellation.

The skill supports GitHub only. It does not create issues, plan product work,
implement changes, review pull requests, or merge pull requests.

## Quick reference

| Request | Result |
|---|---|
| `status issue 75` | Show the issue state and recommend the next available work. |
| `start issue 75` | Create or reuse the issue branch and worktree, then stop before implementation. |
| `config` | Inspect or configure workflow settings and assigned-board mappings. |
| `finish issue 75` | Validate, commit, push, and prepare an unmerged pull request. |
| `clean issue 75` | Remove eligible artifacts from completed work after confirmation. |
| `clean` | List residual repository branches and let you select cleanup candidates. |
| `force clean` | Include unmerged, divergent, dirty, or active candidates with explicit warnings. |
| `cancel issue 75` | Close abandoned work as `Not planned` and remove its artifacts after confirmation. |

`start` prepares the workspace but does not implement the issue. `finish`
prepares the pull request but does not merge it. Repository cleanup does not
close issues or pull requests. Use `cancel` when you also want to close
abandoned work.

## Requirements

Install these tools before you use the skill:

- Git
- [GitHub CLI](https://cli.github.com/) with access to the target repository
- `jq`

Supacode is optional. The skill can use native Git worktrees when Supacode is
unavailable or disabled.

## Installation

Install `gh-issue` globally for Codex, Claude Code, and GitHub Copilot:

```text
npx skills@latest add ukchucktown/agent-skills --skill gh-issue --agent codex --agent claude-code --agent github-copilot --global --yes
```

The Agent Skills CLI uses your existing Git or GitHub CLI authentication for
this private repository.

## Use the skill

Invoke the skill by name or use an unambiguous natural-language request. These
requests start the same workflow:

```text
gh-issue start 75
start issue 75
issue 75 start
GitHub issue 75 start
```

The skill does not act on a bare issue reference. It also does not treat a
request to discuss, create, review, prioritize, close, or merge an issue as a
workflow command.

## Workflows

### Status

Use `status` to inspect an issue and identify the next available issue in a
compound effort:

```text
gh-issue status 75
what is the status of issue 75?
```

The status workflow reads the issue hierarchy, blockers, configured GitHub
Project status, and bounded branch evidence. It does not change local or remote
state.

For a compound issue, the status workflow recommends the first open, unblocked
standalone issue that has no branch evidence. Branch evidence is a linked
branch or a local worktree on a branch name that contains the issue number. The
walk follows GitHub hierarchy order and tries the next sibling when a compound
issue has no candidate. The walk stops at the first candidate or after 25 issue
queries.

The `Skipped as started` block lists the started issues that the walk passed.
The status workflow cannot tell paused work from active work, so the block
shows the evidence and you decide. Each local worktree of a skipped issue has
these items:

- The worktree path and its branch.
- The number of open Supacode tabs, when Supacode manages the worktree. The tab
  of the current session does not count.
- The number of branch commits that no other branch contains, and the age of
  the last commit.
- The number of uncommitted changes.

An open Supacode tab alone does not prove active work. Supacode keeps a tab
open after the work stops.

If you omit the issue number, the skill presents a short list of recent open
issues that you authored or that GitHub assigned to you. The skill waits for
you to select an issue.

### Start and resume

Use `start` to prepare work for an existing issue:

```text
gh-issue start 75
start issue 75
```

The start workflow handles these tasks:

1. Resolve the issue and its ancestor hierarchy.
2. Reuse an existing issue branch or worktree when one exists.
3. Use an established repository branch pattern when the evidence is clear.
4. Create the necessary remote branch and local worktree when work does not
   exist.
5. Assign the authenticated user when the issue has no assignee.
6. Apply the configured start values to assigned GitHub Project boards.
7. Stop before implementation starts.

One checked-in command performs the complete start or resume workflow. The
agent does not coordinate separate GitHub, Git, Project, or worktree-manager
calls and does not delegate this deterministic work to another agent.

If required evidence conflicts, the command returns one structured question
before it changes state. The skill asks that question and reruns the command
with the selected branch, base, destination, manager, or confirmed worktree
path. It does not use more searches to guess the answer.

Start preserves existing assignees and reports their names. Before branch
creation, start checks whether each ancestor branch lacks commits from its
higher branch. If an ancestor is behind or divergent, the command reports the
missing commit count and requests a base.

Use `resume` when a linked remote branch exists without a local worktree. The
skill attaches that branch through the configured worktree manager.

Before `start` or `resume` attaches an existing worktree, the command collects
the same evidence as the status workflow. The worktree looks in use when it has
an open Supacode tab or uncommitted changes. The tab of the current session does
not count. If the worktree looks in use, the command makes no change and asks
you to confirm. The question shows the path and the evidence. After you
confirm, the skill reruns the command with `--accept-in-use PATH`. The path
must be the path that the question shows. A worktree that does not look in use
attaches with no question.

Supacode keeps a tab open after work stops. For this reason, Supacode users can
see this question for a worktree that no session uses.

### Finish

Use `finish` after the issue work is ready for review:

```text
gh-issue finish 75
finish issue 75
```

The finish workflow reviews the issue branch, validates the intended changes,
commits those changes, pushes the branch, and prepares a ready-for-review pull
request. The pull request targets the resolved parent or stable branch and ends
with `Closes #75`.

Finish accepts uncommitted work and reports it separately from committed paths.
The report includes staged changes, unstaged changes, and untracked files. The
agent reviews these files before it commits the intended changes. Unresolved
conflicts block finish. Uncommitted work prevents automatic issue closure,
including when an earlier pull request merged.

Finish fetches the base branch from origin before it computes the changed
paths. The comparison uses the fetched remote branch. A local branch supplies
the base only when origin has no branch with that name. A remote lookup or fetch
failure blocks finish, so stale local references cannot hide a remote failure.
Finish leaves the local base branch unchanged.

The skill never merges the pull request. If the issue has no changes and no
pull request, the workflow closes verified no-change work as completed.

### Clean an issue effort

Use `clean` with an issue number after GitHub merges the work:

```text
gh-issue clean 75
```

The plan covers the issue and its sub-issues in the same repository. It does
not include the parent issue. Thus, you can clean a merged task while its epic
stays open. The plan
can include eligible issue worktrees and local or remote branches. The skill
asks for confirmation before it deletes any item.

The stable branch is the branch that the primary checkout is on. It can be a
long-lived feature branch instead of the default branch. Cleanup never removes
the stable branch or the default branch.

The normal cleanup preserves these items:

- A branch whose name or link refers to an open issue, also an issue outside
  the plan
- A dirty or unavailable worktree
- The active checkout
- A protected branch
- A branch with an open pull request
- Divergent local and remote branch tips
- Work that the skill cannot verify in the stable branch

### Clean repository artifacts

Use `clean` without an issue number to find residual branch groups across the
current repository:

```text
gh-issue clean
```

The workflow first lists every selectable branch group and every blocked group.
Each branch appears once, with its worktree, local and remote references,
warnings, and planned actions grouped beneath it. Select `all`, a
comma-separated list such as `2,4,7`, a range such as `2-6`, or exact branch
names. The skill then shows the exact deletion plan and asks for one
confirmation.

`all` selects every safe candidate. It does not enable force cleanup.

Repository cleanup accepts a squash-merged branch only if GitHub records the
branch tip as a merged pull request's exact head.

Use force cleanup only when you intend to discard unmerged, divergent, dirty,
or Supacode-active work:

```text
gh-issue force clean
```

Force cleanup displays each risk as a warning. It still protects the stable
checkout, protected branches, branches with open pull requests, unavailable
worktrees, and branches that multiple worktrees use.

Repository cleanup does not close issues or pull requests.

### Cancel an abandoned effort

Use `cancel` when you want to abandon an issue effort:

```text
gh-issue cancel 75
cancel issue 75
```

Cancellation resolves the top-level effort and prepares one combined plan. It
reads all of the sub-issues of the effort, with no limit on their number. The
plan can close open issues as `Not planned`, close open pull requests without a
merge, and remove associated branches and worktrees. Cancellation stops before
it changes any item when the effort includes an issue in another repository.

Cancellation can discard unmerged commits, divergent tips, uncommitted
changes, and Supacode-active worktrees. The skill reports the full plan and
asks for confirmation before it changes any item.

Cancellation never removes the stable checkout, the default branch, a
protected branch, an unrelated branch, an unavailable worktree, or a branch that multiple worktrees
use.

## Configuration

The skill uses one local configuration file with global, organization, and
repository tiers. More specific settings override broader settings. Explicit
command options apply only to the current invocation.

Use `gh-issue config` with a repository and an issue to discover that issue's
assigned GitHub Project boards. The workflow displays field choices and current
mappings. You can select start and completion values for each managed field or
leave a board unmanaged. The workflow presents a preview before it saves changes.

Only boards assigned to the issue participate. A configured but unassigned board
remains untouched. The skill does not add issues or ancestors to boards. Names
use case-insensitive lookup, and updates use the resolved GitHub IDs. Ambiguous
names require a choice.

Start applies values after the workspace exists. Finish applies completion
values after confirmed completion, including a previously completed issue with
a stale board value. PR preparation does not trigger Done. GitHub automation
handles completion outside a skill invocation. Read-only status reports any
differences without a write.

The [configuration reference](../skills/engineering/gh-issue/references/start-config.md)
defines the schema, precedence, command arguments, migration, and retry behavior.

## Safety model

The workflow keeps destructive operations separate from discovery and
planning. Cleanup and cancellation use this sequence:

1. Discover the eligible and blocked items without a state change.
2. Let the user select the applicable items.
3. Produce an exact plan and confirmation token without a state change.
4. Request confirmation immediately before the mutation.
5. Apply only the confirmed plan.

If repository state changes before confirmation, the token becomes stale. The
skill creates a new plan and requests a new confirmation.

The commands emit discovery results and detailed plans as one buffered block.
This command-level buffer prevents incremental terminal redraws. It does not
control how a desktop client renders the assistant response. The skill puts
each complete result in one fenced `text` code block. This format provides one
copyable plain-text region and avoids per-branch Markdown pills.

A valid confirmation prints only a compact count summary before the command
applies the plan. The command does not repeat every branch and worktree. A
stale confirmation still prints the complete refreshed plan for review.

Forced repository cleanup tolerates a selected Git worktree that acquires a
lock after the command creates the plan. If any apply-time operation still
fails, the command reports the completed deletion counts and requires fresh
discovery before a retry.

The skill uses bounded GitHub queries and focused local inspection. It does not
search every pull request, branch, worktree, or issue to increase confidence.
When required evidence conflicts, it reports the conflict and waits for the
user.

## Development validation

Run the isolated command suite from the repository root:

```sh
sh tests/gh-issue/run.sh
```

The test harness requires Python, but the installed skill uses Node.js and shell.
The tests use temporary configuration and repositories with mocked GitHub calls.

Measure helper startup and local configuration resolution:

```sh
node tests/gh-issue/benchmark-projects.mjs
```

The benchmark reports the median and 95th percentile of elapsed process time.
It uses synthetic configuration and starts a new process for each sample.
It measures no GitHub requests or worktree operations. Runtime versions and
machine load affect the results. The optional `--python-baseline PATH` argument
compares a saved copy of the previous helper with the same fixtures.
