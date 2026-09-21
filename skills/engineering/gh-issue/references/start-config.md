# Start configuration

`gh-issue` reads optional machine settings from
`~/.config/agent-skills/config.json`. Settings use this top-level schema:

```json
{
  "schemaVersion": 1,
  "worktreeManager": "auto",
  "worktreeRoot": "/absolute/path/to/worktrees",
  "repositories": {
    "OWNER/REPOSITORY": {
      "efforts": {
        "123": {
          "integrationBranch": "feat/shared-effort",
          "taskBranchTemplate": "feat/work-{number}-{slug}",
          "worktreeTemplate": "work-{number}-{slug}"
        }
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

Repository keys use GitHub's case-insensitive `OWNER/REPOSITORY` name. An effort
key is the number of a compound issue. Its policy applies when that issue is
the requested issue or one of its ancestors. If several efforts match, use the
one nearest the requested issue.

A fixed `integrationBranch` means all matching compound and task issues share
that integration branch. It prevents the workflow from generating one branch
per ancestor. Branch and worktree templates accept `{number}` and `{slug}`.
Use a short, lowercase, hyphenated slug. It may omit redundant effort words and
articles.

Explicit user or loaded repository instructions override this file. A matching
effort overrides generic defaults. If no policy matches and no exact issue
branch exists, show the generic layout and ask. Apply it only after the user
accepts it.
