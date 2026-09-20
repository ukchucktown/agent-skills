# Repository guidance

## Purpose

This repository is the canonical source for Grant Lewis's Agent Skills,
cross-harness instruction fragments, and deterministic workflow helpers.

## Skill design

- Keep each promoted skill independently installable.
- Use `SKILL.md` for essential decisions and steps. Put conditional detail in
  linked references.
- Prefer deterministic, dependency-free scripts for repeated Git, GitHub,
  configuration, and worktree operations.
- Keep user-invoked skills explicit. Shared skills may be model-invoked when
  another skill must reach them.
- Validate scripts through isolated fixtures. Tests must not inspect or change
  real skill installations, repositories, GitHub issues, or worktrees.

## Repository structure

- `skills/engineering/` contains promoted engineering workflows.
- `skills/writing/` contains promoted writing skills.
- `skills/in-progress/` contains skills that are not yet promoted.
- `skills/deprecated/` contains retired skills kept for reference.
- `docs/` contains human-facing guidance and architectural decisions.
- `scripts/` contains repository maintenance commands.
- `tests/` contains isolated behavioral tests.

## Delivery

- Keep the primary checkout on `main`.
- Follow the global Supacode worktree convention for every task branch.
- Commit and push reviewed changes on feature branches. Do not push feature
  work directly to `main`.
- Keep the repository private unless the user explicitly changes that choice.
