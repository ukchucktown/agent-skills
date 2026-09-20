# Personal agent workflow

Use `sdlc-plan-work` to plan new work and decide whether it needs a coordinated
feature. Use `sdlc-status` to recover progress and identify the next valid
command. Use the issue and feature finish skills for their review and approval
boundaries.

Keep each repository's primary checkout on its stable branch. Create task
worktrees under the machine profile's `worktreeRoot`. Use its configured
worktree manager, and keep coordinated child worktrees until the full feature
reaches the stable branch.

The final integration-to-stable merge always requires explicit user approval.
