# Workflow configuration

The skill uses one local file: `~/.config/agent-skills/config.json`.
`AGENT_SKILLS_CONFIG` selects another file for isolated use. The commands require
Node.js 22 or later, Git, GitHub CLI, and jq. The Node helper uses built-in modules.
It requires no package installation or build step. The existing shell commands
remain the public entry points.

## Inheritance

Precedence runs from lowest to highest: global settings, organization settings,
repository settings, and explicit invocation options. The organization key is
the repository owner. Personal account owners also work as keys. A board owner
can differ from the repository owner.

The `config` result includes each effective setting and its source. Omitted
settings inherit. Board mappings merge by owner and project number. Field
mappings merge by field selector. An explicit `enabled: false` disables a board
without questions on later issues. A narrower tier can enable it again.

This example uses synthetic owners and board numbers:

```json
{
  "schemaVersion": 2,
  "worktreeManager": "auto",
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

`worktreeManager` accepts `auto`, `supacode`, or `git`. The `auto` setting uses
Supacode when it contains the primary repository. Otherwise, it uses native Git.
`worktreeRoot` contains a directory for each repository. Without an explicit
root, the skill uses a worktrees directory beside the primary checkout's container.

`integrationBranchTemplate`, `taskBranchTemplate`, and `worktreeTemplate` require
`{number}` and `{slug}`. Explicit branch and manager options override resolved
settings. Existing issue branches take precedence over templates.

`taskBaseBranch` selects an existing base for tasks without direct children.
Start omits intermediate ancestor branches for those tasks. Finish uses that
base for a new pull request. An explicit `--base` takes precedence. An existing
pull request keeps its base. Compound issues still use their ancestor hierarchy.

Without a task base, start compares existing ancestor branches with the next
higher branch and compares the highest ancestor with the default branch. Missing
commits require a base choice. The command preserves ancestor branches.
