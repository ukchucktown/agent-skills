# SDLC lifecycle

GitHub holds the shared state. The local checkout holds policy and machine
preferences. A missing local worktree must not hide work done by a teammate.

Record an adopted integration branch in a parent comment with
`<!-- agent-skills:sdlc-integration-branch:<branch> -->`. Record a child branch
with `<!-- agent-skills:sdlc-branch:<branch> -->`. These markers preserve
existing branch names that predate the configured templates. Never put a local
worktree path in either comment.

## Feature states

| State | Meaning | Next transition |
|---|---|---|
| `planned` | The parent is open and no child work has started | Start the first ready child |
| `in_progress` | A child has started or completed on the integration branch | Continue, review, or start a ready child |
| `ready_to_finish` | Every child is complete | Plan the final feature merge |
| `complete` | The feature reached the stable branch | Clean retained worktrees and branches |
| `cancelled` | The reviewed cancellation plan was applied | Keep the audit trail |

## Child states

| State | Meaning | Next transition |
|---|---|---|
| `blocked` | One or more GitHub blockers remain open | Finish a blocker |
| `ready` | The child is open and has no open blocker | Start the issue |
| `in_progress` | A branch, worktree, or open pull request exists | Continue the issue |
| `review` | The pull request targets the integration branch and awaits a gate | Review or merge the pull request |
| `complete` | The child pull request merged into the integration branch | Keep its worktree until the feature completes |
| `cancelled` | The issue closed without an accepted child merge | Keep the audit trail |

A merged pull request wins over local worktree evidence. An open GitHub blocker
wins over a ready label. The runtime reports inconsistent evidence instead of
silently choosing a destructive action.

## Pull request rules

- A child pull request targets its feature integration branch.
- A child pull request closes exactly one child issue.
- All GitHub blockers and required checks must pass before a child merge.
- A stable-branch pull request for a coordinated feature comes from the
  integration branch.
- The user approves the final merge.

## Worktree retention

Keep child worktrees while the feature remains active. After the feature merge,
remove only a clean worktree whose branch reached the stable branch. Report a
dirty, unmerged, or unknown worktree for human review.
