import { basename, join, resolve } from "node:path";

import { renderPattern } from "../../../sdlc-workflow/scripts/lib/config.mjs";
import { fingerprint } from "../../../sdlc-workflow/scripts/lib/json.mjs";
import { validateAction } from "../../../sdlc-workflow/scripts/lib/plan.mjs";

function labels(issue) {
  return (issue.labels ?? []).map((label) => typeof label === "string" ? label : label.name);
}

function logins(issue) {
  return (issue.assignees ?? []).map((assignee) =>
    typeof assignee === "string" ? assignee : assignee.login);
}

function marker(branch) {
  return `<!-- agent-skills:sdlc-branch:${branch} -->`;
}

export function createStartPlan({
  snapshot,
  repositoryConfig,
  machineConfig,
  repositoryRoot,
  overrideAssignment,
}) {
  const issue = snapshot.issue;
  if (!issue || issue.state !== "open") throw new Error(`issue #${issue?.number ?? "?"} is not open`);
  if (!labels(issue).includes(repositoryConfig.childLabel)) {
    throw new Error(`issue #${issue.number} is not labeled '${repositoryConfig.childLabel}'`);
  }
  if (!snapshot.parent || !labels(snapshot.parent).includes(repositoryConfig.featureLabel)) {
    throw new Error(`issue #${issue.number} has no configured feature parent`);
  }
  if (snapshot.parent.state !== "open") {
    throw new Error(`feature issue #${snapshot.parent.number} is not open`);
  }
  const openBlockers = snapshot.blockers.filter((blocker) => blocker.state !== "closed");
  if (openBlockers.length > 0) {
    throw new Error(
      `issue #${issue.number} has open blockers: ${openBlockers.map((blocker) => `#${blocker.number}`).join(", ")}`,
    );
  }
  if (snapshot.pullRequests.length > 0) {
    throw new Error(
      `issue #${issue.number} already has pull request(s): ${snapshot.pullRequests.map((pull) => `#${pull.number}`).join(", ")}`,
    );
  }
  if (!snapshot.integrationBranchExists) {
    throw new Error(`integration branch '${snapshot.integrationBranch}' does not exist`);
  }

  const otherAssignees = logins(issue).filter((login) => login !== snapshot.actor);
  if (otherAssignees.length > 0 && !overrideAssignment?.trim()) {
    throw new Error(
      `issue #${issue.number} is assigned to ${otherAssignees.map((login) => `@${login}`).join(", ")}; an explicit override reason is required`,
    );
  }

  const branch = snapshot.branch ?? renderPattern(
    repositoryConfig.childBranchPattern,
    issue.number,
    issue.title,
  );
  const issueWorktrees = snapshot.worktrees.filter((worktree) => worktree.branch === branch);
  if (snapshot.branchExists && issueWorktrees.length === 0) {
    throw new Error(`branch '${branch}' exists without a local worktree; inspect ownership before reuse`);
  }
  if (issueWorktrees.length > 1) {
    throw new Error(`branch '${branch}' has multiple local worktrees`);
  }

  const repositoryName = basename(resolve(repositoryRoot));
  const worktreeName = `issue-${issue.number}-${issue.title
    .normalize("NFKD")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 40) || "work"}`;
  const worktreeParent = join(machineConfig.worktreeRoot, repositoryName);
  const worktreeRoot = join(worktreeParent, worktreeName);
  const actions = [];
  if (issueWorktrees.length === 0) {
    actions.push({
      id: "create-worktree",
      adapter: "worktree",
      operation: "create",
      parameters: {
        repositoryRoot: resolve(repositoryRoot),
        branch,
        base: `origin/${snapshot.integrationBranch}`,
        fetchBranch: snapshot.integrationBranch,
        location: worktreeParent,
        name: worktreeName,
        root: worktreeRoot,
        manager: machineConfig.worktreeManager,
      },
    });
  }
  for (const assignee of otherAssignees) {
    actions.push({
      id: `unassign-${assignee}`,
      adapter: "github",
      operation: "unassign-issue",
      parameters: { issue: issue.number, assignee },
    });
  }
  if (!logins(issue).includes(snapshot.actor)) {
    actions.push({
      id: "assign-issue",
      adapter: "github",
      operation: "assign-issue",
      parameters: { issue: issue.number, assignee: snapshot.actor },
    });
  }
  if (labels(issue).includes(repositoryConfig.readyLabel)) {
    actions.push({
      id: "remove-ready-label",
      adapter: "github",
      operation: "remove-label",
      parameters: { issue: issue.number, label: repositoryConfig.readyLabel },
    });
  }
  const branchMarker = marker(branch);
  const hasBranchComment = snapshot.comments.some((comment) => comment.body?.includes(branchMarker));
  if (!hasBranchComment || otherAssignees.length > 0) {
    const override = otherAssignees.length > 0
      ? `\n\nAssignment override: @${snapshot.actor} took over from ${otherAssignees.map((login) => `@${login}`).join(", ")}. Reason: ${overrideAssignment.trim()}`
      : "";
    actions.push({
      id: "record-branch",
      adapter: "github",
      operation: "comment",
      parameters: {
        issue: issue.number,
        body: `Started on branch \`${branch}\`, based on \`${snapshot.integrationBranch}\`.${override}\n\n${branchMarker}`,
      },
    });
  }
  for (const [index, action] of actions.entries()) validateAction(action, index);

  const evidence = { fingerprint: fingerprint(snapshot) };
  const content = {
    schemaVersion: 1,
    operation: "start-issue",
    repositoryRoot: resolve(repositoryRoot),
    repository: snapshot.repository,
    issue: issue.number,
    branch,
    integrationBranch: snapshot.integrationBranch,
    worktree: issueWorktrees[0] ?? {
      id: null,
      root: worktreeRoot,
      branch,
      manager: machineConfig.worktreeManager,
    },
    evidence,
    actions,
  };
  return { ...content, planId: fingerprint(content) };
}

export async function applyStartPlan({ plan, inspect, adapters }) {
  const current = await inspect();
  if (fingerprint(current) !== plan.evidence.fingerprint) {
    throw new Error("start plan is stale; inspect the issue and plan again");
  }
  const content = { ...plan };
  delete content.planId;
  if (fingerprint(content) !== plan.planId) throw new Error("start plan content does not match its planId");

  let worktree = plan.worktree;
  const receipts = [];
  for (const [index, rawAction] of plan.actions.entries()) {
    const action = validateAction(rawAction, index);
    const adapter = adapters[action.adapter];
    if (!adapter?.execute) throw new Error(`no start adapter for '${action.adapter}'`);
    const result = await adapter.execute(action.operation, action.parameters);
    if (action.adapter === "worktree") worktree = result;
    receipts.push({ actionId: action.id, result: result ?? null });
  }
  return {
    schemaVersion: 1,
    status: "prepared",
    planId: plan.planId,
    repository: plan.repository,
    issue: plan.issue,
    branch: plan.branch,
    integrationBranch: plan.integrationBranch,
    worktree,
    receipts,
  };
}
