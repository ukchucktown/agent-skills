# Agent Skills

Personal Agent Skills and deterministic workflows for Codex, Claude Code, and
GitHub Copilot.

Skills under `skills/in-progress/` are reviewable but not yet promoted for
general installation. Promoted skills remain independently selectable.

Current work:

- `gh-issue` — lightweight GitHub issue mechanics with a read-only status
  foundation. `start`, `finish`, and `clean` remain intentionally unavailable
  until their deterministic implementations are reviewed.

Run `npm test` from the repository root to validate the deterministic helpers.
