# Contributing

Keep each change within one issue and one skill or workflow outcome. Read the
root `AGENTS.md` before work starts.

## Add or change a skill

1. Put a promoted skill in its subject bucket under `skills/`.
2. Put an unfinished skill in `skills/in-progress/`.
3. Keep the directory name equal to the `name` in `SKILL.md`.
4. Put essential instructions in `SKILL.md` and conditional detail in linked
   references.
5. Add isolated tests for deterministic scripts.
6. Add a changeset for a user-visible change.
7. Run `npm test` before a commit.

Move a retired skill to `skills/deprecated/`. Add its replacement and migration
path to the skill before the move.

## Submit work

Create a feature branch from the correct base branch. Open a pull request with
the issue number and the commands used to verify the change. Do not place a
local worktree path in an issue or pull request.

The repository is private. A contribution does not authorize publication,
public visibility, or npm release.
