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
  "worktreeTemplate": "issue-{number}-{slug}"
}
```

`worktreeManager` accepts `auto`, `supacode`, or `git`. `auto` uses Supacode
when the primary repository is registered. Otherwise, it uses native Git.

`worktreeRoot` contains one directory per repository. If it is absent, the
default is a `worktrees` directory beside the directory that contains the
primary checkout.

Branch and worktree templates accept `{number}` and `{slug}`. Use a short,
lowercase, hyphenated slug. It may omit redundant effort words and articles.

Explicit user or loaded repository instructions override this file. Existing
issue branches and a clearly established shared integration pattern override
generic templates. When the evidence is ambiguous, ask. Do not add a
repository-specific exception to this file.
