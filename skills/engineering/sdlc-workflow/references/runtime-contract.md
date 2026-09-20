# Runtime contract

The runtime separates observation, planning, and effects.

## Inspect

An inspector reads these inputs:

- `docs/agents/sdlc.md` YAML frontmatter
- the machine profile JSON
- a GitHub adapter snapshot
- a worktree adapter snapshot

It normalizes the values, derives workflow states, and hashes the complete
observation. Inspection creates no file unless the caller requests an output
file.

## Plan

A planner accepts a workflow state and a typed request. It validates each
action against the allowed adapter operations. The plan records the observation
fingerprint and gets its own deterministic ID.

A plan contains no credential and no executable shell text.

## Apply

An apply command inspects the live sources again. It rejects the plan when the
new fingerprint differs from the plan fingerprint. It then sends each action
to its named adapter and records a receipt.

The core engine knows these adapter names:

- `github`
- `git`
- `worktree`
- `filesystem`

Each adapter exposes only named operations. An adapter may translate a named
operation to an API call or a structured executable and argument array.

## Stable JSON

The runtime sorts object keys and stable collections before output. The same
inputs produce the same JSON and the same fingerprint on macOS, Linux, and
Windows.

Runtime JSON uses `schemaVersion: 1`. A breaking shape change increments that
integer. Repository configuration uses the same independent schema integer.
