# Start configuration

`gh-issue start` reads optional machine settings from
`~/.config/agent-skills/config.json`:

```json
{
  "gh-issue": {
    "worktreeManager": "auto",
    "worktreeRoot": "/absolute/path/to/worktrees",
    "integrationBranchTemplate": "integration/issue-{number}-{slug}",
    "taskBranchTemplate": "feat/issue-{number}-{slug}",
    "worktreeTemplate": "issue-{number}-{slug}"
  }
}
```

`worktreeManager` accepts `auto`, `supacode`, or `git`. `auto` uses Supacode
when the primary repository is registered and otherwise uses native Git.

`worktreeRoot` contains one directory per repository. If it is absent, the
default is a `worktrees` directory beside the directory that contains the
primary checkout.

Branch and worktree templates accept `{number}` and `{slug}`. Command-line
`--manager` and `--worktree-root` values override the configuration file.
