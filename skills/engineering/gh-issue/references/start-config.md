# Start configuration

`gh-issue` reads optional machine settings from
`~/.config/agent-skills/config.json`. Settings use this top-level schema:

```json
{
  "schemaVersion": 1,
  "worktreeManager": "auto",
  "worktreeRoot": "/absolute/path/to/worktrees",
  "integrationBranchTemplate": "integration/issue-{number}-{slug}",
  "taskBranchTemplate": "feat/issue-{number}-{slug}",
  "worktreeTemplate": "issue-{number}-{slug}",
  "projectStatus": {
    "enabled": true,
    "owner": "OWNER",
    "number": 2,
    "field": "Status",
    "startOption": "In Progress"
  },
  "repositories": {
    "OWNER/REPOSITORY": {
      "projectStatus": {
        "enabled": false
      }
    }
  }
}
```

`worktreeManager` accepts `auto`, `supacode`, or `git`. `auto` uses Supacode
when the primary repository is registered. Otherwise, it uses native Git.

`worktreeRoot` contains one directory per repository. If it is absent, the
default is a `worktrees` directory beside the directory that contains the
primary checkout.

Branch and worktree templates accept `{number}` and `{slug}`. Use a short,
lowercase, hyphenated slug. It may omit redundant effort words and articles.

Top-level Project status synchronization applies only to repositories whose
owner matches `projectStatus.owner`. `owner` and the positive integer `number`
identify the target Project so start can add an issue that is not yet a Project
item. The field defaults to `Status`, and the start option defaults to `In
Progress`.

An exact repository entry overlays the matching top-level default. It can set
`enabled` to `false` or override the Project, field, or start option. An exact
entry can also enable Project status for a repository owned by someone else.
The earlier per-repository shape remains valid without `owner` and `number`; it
updates matching Projects only when the issue is already a Project item.

Enabled repositories require GitHub CLI authentication with `read:project` and
`project` scopes. Repositories without an effective enabled setting make no
Project query or mutation.

When either scope is missing, report this corrective command and stop before
start mutations. Do not run the interactive authentication command for the
user:

```text
gh auth refresh -s read:project,project
```

When an explicit target Project is configured, add the focused issue and its
open ancestors when they are missing, then set the configured start option. For
the earlier per-repository shape, update every existing Project with one exact
field and option match. Stop before branch creation when the configured match is
missing, duplicated, truncated, or inaccessible.

Explicit user or loaded repository instructions override this file. Existing
issue branches and a clearly established shared integration pattern override
generic templates. When the evidence is ambiguous, ask. Do not add a
repository-specific exception to this file.
