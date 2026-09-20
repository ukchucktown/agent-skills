---
name: sdlc-setup
description: Configure a GitHub repository for the cross-harness SDLC workflow. Use when the user asks to set up, adopt, configure, or repair the sdlc-* workflow, integration branch policy, GitHub labels, repository instructions, or PR contract automation.
disable-model-invocation: true
---

# SDLC setup

Configure one repository and preserve its own instructions.

## Plan the setup

1. Read `../sdlc-workflow/references/lifecycle.md`.
2. Inspect the repository and its current `AGENTS.md`, `CLAUDE.md`, Copilot
   instructions, Matt Pocock skill references, SDLC configuration, and GitHub
   labels.
3. Create a settings JSON file only when the defaults need an override.
4. Run the setup script in plan mode.
5. Show the plan, the detected Matt configuration, and every proposed file and
   label change to the user.

```bash
node skills/engineering/sdlc-setup/scripts/setup.mjs plan \
  --repository . \
  --output /tmp/sdlc-setup-plan.json
```

Use `--settings <file>` for overrides. The file accepts the repository
configuration keys in the shared schema.

## Apply the reviewed plan

Apply only the plan that the user reviewed:

```bash
node skills/engineering/sdlc-setup/scripts/setup.mjs apply \
  --plan /tmp/sdlc-setup-plan.json
```

The apply phase reads every source again and rejects stale evidence. It writes
only marked instruction blocks, the owned SDLC document, and the owned GitHub
automation files. It creates or updates only the three configured labels.

## Defaults

- Stable branch: `main`
- Integration branches: `integration/issue-{issue}-{slug}`
- Child branches: `feat/issue-{issue}-{slug}`
- Child and final merge method: merge commit
- Worktree retention: until the feature reaches the stable branch
- Child auto-merge: enabled after required checks and review
- Final merge: explicit user approval

Use structured validation commands such as
`{"executable":"npm","args":["test"]}`. Never put a shell string in the
configuration.
