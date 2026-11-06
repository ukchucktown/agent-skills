# Workflow configuration

The skill uses one local file: `~/.config/agent-skills/config.json`.
`AGENT_SKILLS_CONFIG` selects another file for isolated use. A shared workspace
can also supply layout settings in a `.gh-issue.json` file. The
[workspace file](#workspace-file) section describes that file.

The commands require Node.js 22 or later, Git, GitHub CLI, and jq. The Node
helper uses built-in modules. It requires no package installation or build step.
The existing shell commands remain the public entry points.

## Inheritance

Precedence runs from lowest to highest: global settings, organization settings,
the workspace file, repository settings, and explicit invocation options. The
organization key is the repository owner. Personal account owners also work as
keys. A board owner can differ from the repository owner.

The `config` result includes each effective setting and its source. Omitted
settings inherit. Board mappings merge by owner and project number. Field
mappings merge by field selector. An explicit `enabled: false` disables a board
without questions on later issues. A narrower tier can enable it again.

This example uses synthetic owners and board numbers:

```json
{
  "schemaVersion": 2,
  "projectSync": {
    "enabled": true,
    "ancestors": true,
    "boards": {}
  },
  "organizations": {
    "example": {
      "projectSync": {
        "boards": {
          "example/4": {
            "fields": {
              "Status": {
                "start": "In progress",
                "complete": "Done"
              }
            }
          }
        }
      }
    }
  },
  "repositories": {
    "example/service": {
      "projectSync": {
        "boards": {
          "example/4": {"enabled": false},
          "delivery/5": {
            "fields": {
              "Delivery stage": {
                "start": "Building",
                "complete": "Shipped"
              }
            }
          }
        }
      }
    }
  }
}
```

Board keys use `OWNER/NUMBER`. A board title is display metadata, not a unique
identity. Field selectors and transition options use case-insensitive names.
The `id:GRAPHQL_ID` form selects an exact field or option ID when names are
ambiguous. IDs remain case-sensitive. Updates use the resolved GitHub IDs.
Multiple selectors for the same field are invalid.
To disambiguate an inherited field, keep its existing selector key and set
`fieldId` inside its mapping to the exact field ID. The narrower tier then
selects that field and retains inherited transitions.

Only assigned boards participate. A configured but unassigned board receives no
read or write for its field metadata. The skill never adds an issue to a board.
An issue without assigned boards needs no setup. With `projectSync.enabled`
set to `false`, runtime commands make no project queries or updates. The config
command can still discover assigned boards for setup.

## Config workflow

Inspect effective settings:

```text
<skill-directory>/scripts/config.sh OWNER/REPOSITORY
```

Discover the boards assigned to an issue:

```text
<skill-directory>/scripts/config.sh OWNER/REPOSITORY --issue NUMBER
```

The result includes assigned boards, available single-select fields and options,
effective mappings, and unresolved choices. A `needs_input` result means that
the user must select fields and values or leave the board unmanaged. Ask about
the unresolved choices. Do not infer field meaning from its name alone.

Prepare a tier patch as a JSON argument. `--scope` accepts `global`,
`organization`, or `repository` and defaults to `repository`. A board patch
requires `--issue`. The command rejects a board absent from that issue.

```text
<skill-directory>/scripts/config.sh OWNER/REPOSITORY --issue NUMBER --scope organization --set JSON
```

Use the harness's structured argument support or correct shell quoting for the
JSON. A patch has the same settings shape as one tier. For example, a patch
can contain `projectSync.boards` with selected field transitions. Include
`projectSync.enabled: true` to enable synchronization over an inherited disabled
setting. Set a board's `enabled` value to `false` to leave it unmanaged.

The command returns the old configuration, the proposed configuration, the
effective result, the selected scope, and a confirmation token. Present that
preview. Request acceptance before the write. After acceptance, repeat the same
command with its token:

```text
<skill-directory>/scripts/config.sh OWNER/REPOSITORY --issue NUMBER --scope organization --set JSON --confirm TOKEN
```

The write preserves unrelated settings. A concurrent configuration change or a
change to the discovery result invalidates the token. Present the fresh preview
before another confirmation. The writer uses a lock and an atomic file replacement.
A stale lock reports its path and leaves the configuration unchanged.

`config --override JSON` applies an invocation-only tier and saves nothing.
Start, resume, status, and finish accept `--project-override JSON` for the same
purpose. Put that option before the repository and issue arguments. A saved
patch and an invocation override cannot share a config invocation.

## Lifecycle and failure recovery

Start validates assigned-board mappings before branch or worktree creation.
After the workspace exists, start applies the configured start values. A start
that finds only a remote branch reports the plan and requests resume. Resume
attaches the branch before it applies the values.

`projectSync.ancestors` defaults to `true`, which preserves start propagation
to open ancestors. Each ancestor uses its own repository configuration and board
memberships. Set this flag to `false` to limit start to the focused issue.
Completion always affects only the focused issue.

Finish does not apply Done when it prepares a pull request. It reconciles
completion values after confirmed issue completion, including an issue that
is already complete. A closed, unmerged PR and a not-planned closure do not
qualify. The existing finish rules determine when a merged PR completes the
issue. GitHub automation handles events outside a skill invocation. Read-only
status reports differences without a write.

The shared transition command accepts `start`, `complete`, or `status`:

```text
<skill-directory>/scripts/project-transition.sh EVENT OWNER/REPOSITORY NUMBER --dry-run
```

`--preflight` validates a planned completion before issue closure but never
writes. Apply mode requires a confirmed completed issue for `complete`.
All selected fields pass validation before the first field write. Missing or
ambiguous fields, incomplete data, and inaccessible boards stop the operation.

An update result identifies unchanged, updated, failed, and pending fields.
A partial failure leaves successful writes in place. Retry the original command
after the error is resolved. The command reads current values and writes only
fields that still differ. Project status alone does not establish ownership of
an issue or block recovery of its workspace.

## Legacy migration

The resolver accepts the previous `projectStatus` settings without a file write.
A named shared project becomes an organization mapping with its original owner
restriction. Repository overrides retain their scope. Legacy disabled settings
remain disabled. An unnamed all-boards rule requires explicit board choices.
A legacy start option does not imply a completion option.

A confirmed config write saves schema version 2 and preserves unrelated settings.
The preview shows the migration. It never authorizes automatic board assignment.

## Branch and worktree settings

The skill uses native Git for all worktree operations. The resolver ignores the
retired `worktreeManager` setting at every configuration tier. A confirmed config
write removes that setting from the saved configuration.

These settings control branch names and worktree paths:

| Setting | Default | Variables |
|---|---|---|
| `taskBranchTemplate` | `feat/issue-{number}-{slug}` | `{number}`, `{slug}`, `{key}` |
| `integrationBranchTemplate` | `integration/issue-{number}-{slug}` | `{number}`, `{slug}`, `{key}` |
| `worktreeRoot` | A `worktrees` folder beside the folder that holds the primary checkout | None |
| `worktreeTemplate` | `issue-{number}-{slug}` | `{number}`, `{slug}`, `{key}` |
| `worktreePath` | None | `{root}`, `{workspace}`, `{owner}`, `{repo}`, `{checkout}`, `{branch}`, `{number}`, `{slug}`, `{key}` |
| `branchKey` | None | None |
| `taskBaseBranch` | None | None |

An issue without sub-issues uses the task branch template. An issue with
sub-issues uses the integration branch template, and so does each ancestor of
the issue. The resolver rejects a variable that the setting does not list.

The variables have these values:

- `{number}` is the issue number.
- `{slug}` is the issue title in lowercase ASCII letters and digits. Each run of
  other characters becomes one hyphen. The slug has a maximum of 48 characters.
- `{key}` is the effort key that `branchKey` extracts from the issue title.
- `{root}` is the value of `worktreeRoot`, or its default.
- `{workspace}` is the folder that holds `.gh-issue.json`.
- `{owner}` and `{repo}` are the GitHub owner and the repository name.
- `{checkout}` is the folder name of the primary checkout.
- `{branch}` is the branch of the worktree. A slash in the branch creates
  nested folders.

`worktreePath` holds the complete destination. Without `worktreePath`, the
destination is `{root}/{repo}/` followed by the rendered `worktreeTemplate`.
Only a `worktreePath` that the workspace file supplies can use `{workspace}`.
Start rejects a rendered path that is not absolute. Start also rejects a
variable value that adds an empty, `.`, or `..` folder to the path. The values of
`{root}` and `{workspace}` are exempt.

### Effort key

`branchKey` defines the source of `{key}`. The only source is a title prefix:
a JavaScript regular expression with one capture group.

```json
{"branchKey": {"from": "titlePrefix", "pattern": "^\\[([A-Z]+-[0-9]+)\\]"}}
```

The skill converts the captured text to lowercase and makes no other change.
With this pattern, the title `[TICKET-42] Add export` gives the key `ticket-42`.
A template that uses `{key}` requires `branchKey`. When the issue title has no
match, start returns a question and makes no change. Start rejects a rendered
branch name that `git check-ref-format --branch` rejects.

A branch template without `{number}` can give one name to related issues. For
example, `feat/{key}` gives the branch `feat/ticket-42` to every issue with the
title prefix `[TICKET-42]`, also in different repositories.

### Branch discovery

Start, status, finish, clean, and cancel use one rule to decide which branches
belong to an issue:

1. The linked branches of the issue in the same repository come first.
2. When the issue has no linked branch, the rule uses a name match. A branch
   matches when it fits the effective branch template with the issue number in
   the `{number}` position. `{key}` matches only the key of the issue, and
   `{slug}` matches only lowercase letters and digits in groups that hyphens
   separate. The issue number cannot touch another digit. For a template
   without `{number}`, only the rendered branch name matches.
3. A name match never counts when the branch record names another issue. The
   [branch records](#branch-records) section describes the record.

For the template `feat/issue-{number}-{slug}`, issue #3 matches
`feat/issue-3-fix-timeout`. Issue #3 does not match
`feat/issue-12-retry-3-times`, because 12 is in the `{number}` position.

A possible branch contains the issue number between separators, but the branch
does not match. For example, `fix/3-timeout` is a possible branch for issue #3.
A branch that also fits the template with another number from its name is
ambiguous, and it is a possible branch too. For example, the template
`{slug}-{number}-{slug}` fits `fix-3-retry-12-x` for both #3 and #12.
A possible branch never counts as a match:

- Start asks a question when nothing matches and possible branches exist. The
  candidates are the possible branches and the name of a new branch.
- Finish asks a question when no worktree matches and worktrees on possible
  branches exist.
- Status does not count a possible branch as started work.
- Clean and cancel do not remove a possible branch. The plan lists the branch
  as preserved, with the reason.

Explicit branch options override resolved settings. Existing issue branches take
precedence over templates. A `--branch` value that does not exist names a new
branch, and start creates that branch.

### Branch records

GitHub cannot list the issues that link a given branch. Only a full read of the
open issues could prove that no other issue links a branch. Thus, the skill
keeps a local record instead. When start creates or attaches a branch, start
writes the issue number into the Git configuration of the clone, for example
`branch.feat/ticket-42.gh-issue = 12`. Git deletes the record when it deletes
the local branch. Clean, cancel, and repository cleanup also delete the record
when they remove the last copy of a branch. A record of a branch that no longer
exists in the clone is obsolete and does not count.

Every command reads the record:

- A linked branch whose record names another issue is a conflict. Start and
  finish stop and show the conflict before they select a branch, also for an
  explicit `--branch`. Status does not count the branch as a local worktree of
  the issue. Clean and cancel keep the branch.
- A name match or a possible branch whose record names another issue does not
  belong to the issue.
- Start and finish refuse an explicit `--branch` value whose record names
  another issue.
- A rendered name from a template without `{number}` belongs to the issue only
  through a link or a record of that issue, because other issues can render the
  same name. Without a link or a record, the branch is unverified.
  Start asks before it uses an unverified branch. Finish asks before it selects
  one. Status does not count it as started work. Clean and cancel keep it.

The record covers only the clone that started the work. A branch that another
clone or another person started has no record here. For such a branch, start
asks the question for an unverified branch and does not refuse it. Start also
refuses a destination that holds a worktree on a different branch.

When branches already belong to the issue, `finish --branch` must name one of
them, also when no worktree holds that branch. Without `--branch`, finish
reports an issue branch with no worktree and asks you to resume the issue.

### Clean coverage

Clean with an issue number reads only that issue and the issues whose numbers
appear in branch names. A branch name without an issue number thus enters the
plan only through the cleaned issue itself. To remove the shared
branch of a sub-issue, clean that sub-issue, or use repository cleanup.

### Task base

`taskBaseBranch` selects an existing base for tasks without direct children.
Start omits intermediate ancestor branches for those tasks. Finish uses that
base for a new pull request. An explicit `--base` takes precedence. An existing
pull request keeps its base. Compound issues still use their ancestor hierarchy.

Without a task base, start compares existing ancestor branches with the next
higher branch and compares the highest ancestor with the default branch. Missing
commits require a base choice. The command preserves ancestor branches.

## Workspace file

A workspace can document its layout rules in a `.gh-issue.json` file. The skill
searches for this file in the folder of the primary checkout. Then the skill
searches each parent folder, up to and including the home directory. The
nearest file applies. For a checkout outside the home directory, the search
continues to the root of the file system.

The file can hold only these settings:

- `worktreePath`
- `taskBranchTemplate`
- `integrationBranchTemplate`
- `branchKey`
- `taskBaseBranch`

Any other setting fails validation with a message that names the setting.
`worktreeRoot` is specific to one machine, and board mappings are personal
settings. Thus, both stay in the local file.

The workspace tier is between the organization tier and the repository tier. A
repository setting in the local file overrides the workspace file. The `config`
result names the file in its `workspace` value. The result also shows the file
as the source of each setting that the file supplies. Config never writes the
workspace file. Config finds the primary checkout from the current directory
when that checkout belongs to the target repository. `--checkout PATH` selects
another primary checkout.

This example uses synthetic names. The folder `~/Github/example-workspace/app`
holds the checkouts `web` for `example/app-web` and `api` for `example/app-api`.
The folder also holds this `.gh-issue.json` file:

```json
{
  "worktreePath": "{workspace}/.scratch/worktrees/{branch}/{checkout}",
  "taskBranchTemplate": "feat/{key}",
  "branchKey": {"from": "titlePrefix", "pattern": "^\\[([A-Z]+-[0-9]+)\\]"}
}
```

The issues `example/app-web#12` and `example/app-api#7` both have the title
prefix `[TICKET-42]`. With this file, both issues get the branch
`feat/ticket-42`. The worktrees are `app/.scratch/worktrees/feat/ticket-42/web`
and `app/.scratch/worktrees/feat/ticket-42/api`.
