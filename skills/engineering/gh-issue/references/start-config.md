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
  "repositories": {
    "OWNER/REPOSITORY": {
      "projectStatus": {
        "enabled": true,
        "field": "Status",
        "startOption": "In Progress"
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

Project status synchronization is off unless the exact `OWNER/REPOSITORY` entry
sets `projectStatus.enabled` to `true`. The field defaults to `Status`, and the
start option defaults to `In Progress`. Enabled repositories require GitHub CLI
authentication with `read:project` and `project` scopes. Repositories without
this setting make no Project query or mutation.

When either scope is missing, report this corrective command and stop before
start mutations. Do not run the interactive authentication command for the
user:

```text
gh auth refresh -s read:project,project
```

When an issue belongs to several Projects, update every Project with one exact
field and option match. Stop before branch creation when the configured match is
missing, duplicated, truncated, or inaccessible.

Explicit user or loaded repository instructions override this file. Existing
issue branches and a clearly established shared integration pattern override
generic templates. When the evidence is ambiguous, ask. Do not add a
repository-specific exception to this file.
