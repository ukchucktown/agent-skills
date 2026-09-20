# Lampwright Session setup adoption

Lampwright issue #148 is the first live coordinated feature that uses this
workflow. The adoption kept the existing feature and child history. It added
the shared configuration around that state.

## Recovered state

- Parent: `ukchucktown/lampwright#148`
- Integration branch: `feat/issue-148-session-setup-integration`
- Existing design pull request: #157
- Existing completed child: #149 through pull request #158
- Existing integration issue-close automation: pull request #159
- Remaining children: #150 through #156

GitHub already held all eight native subissue links. The dependency order was
also complete: #150 follows #149, each issue through #155 follows the prior
issue, and #156 follows #153, #154, and #155.

## Adoption preview

Setup plan
`e376bc77d68b4c89f0506572d42a3d17794bb03c6e2fead14a61a2625fdd2274`
listed every change before setup changed the repository. It proposed:

- one marked block in `AGENTS.md`
- one Copilot instruction file
- one versioned repository configuration
- two generic workflow files
- three trusted workflow scripts
- the `sdlc:feature`, `sdlc:child`, and `ready-for-agent` labels

The plan left `CLAUDE.md` unchanged because its existing `@AGENTS.md` pointer
was sufficient. It did not change an issue number, branch, pull request, native
relationship, or implementation file.

Two follow-up previews addressed findings from the live repository. Plan
`683cece20f8f882036059c9dd2e6e237a3f50f8720c30bd763900d6d1d605ddf`
made the trusted Node scripts compatible with Lampwright's strict linter. Plan
`c841a7636a5cef55f1aebc64b341dd468fae4f166d17fff45918e3fd23716207`
added a guard for the first setup pull request, before the trusted scripts
exist on the stable branch.

Pull request #160 delivered the reviewed setup to `main` after the generic
contract and all nine platform jobs passed. The same reviewed commit then
advanced the existing integration branch and preserved its history.

## Live workflow evidence

After adoption, `sdlc-status` reported:

```text
Feature #148: in progress
Complete: #149
Ready: #150
Blocked: #151, #152, #153, #154, #155, #156
Next: /sdlc-start-issue 150
```

Start plan
`7b6d163a4a88279b92de8db9607ca8d5055433e79d6b30b62cc5d9252493e240`
assigned #150, removed its ready label, recorded its branch, and created its
Supacode worktree under the configured Lampwright worktree root.

The first start preview also found that task worktrees were incorrectly used
as Supacode repository identities and repository folder names. The corrected
planner derives the primary checkout and repository folder from the GitHub
repository identity and the machine profile.

## Completion evidence

The pilot keeps the branch-specific close workflow until one remaining child
passes the generic contract, merges into the integration branch, and closes
through the generic workflow. The final pilot record will identify that child
and the automation replacement pull request.
