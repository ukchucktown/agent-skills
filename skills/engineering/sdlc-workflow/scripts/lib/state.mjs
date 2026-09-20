import { fingerprint } from "./json.mjs";
import {
  readMachineConfig,
  readRepositoryConfig,
  renderPattern,
} from "./config.mjs";

function normalizedState(value) {
  return String(value ?? "open").toLowerCase();
}

function sortedUnique(values = []) {
  return [...new Set(values)].sort((left, right) =>
    typeof left === "number" ? left - right : String(left).localeCompare(String(right)),
  );
}

function normalizeIssue(issue, config) {
  const labels = sortedUnique(issue.labels);
  const role = issue.role ??
    (labels.includes(config.featureLabel) ? "feature" :
      labels.includes(config.childLabel) ? "child" : null);
  if (!Number.isInteger(issue.number) || issue.number < 1) {
    throw new Error("every GitHub issue needs a positive integer number");
  }
  if (!role) throw new Error(`issue #${issue.number} has no SDLC role`);

  const pullRequest = issue.pullRequest ? {
    number: issue.pullRequest.number,
    state: normalizedState(issue.pullRequest.state),
    base: issue.pullRequest.base,
    head: issue.pullRequest.head,
    headSha: issue.pullRequest.headSha,
    checks: issue.pullRequest.checks ?? "pending",
    review: issue.pullRequest.review ?? "pending",
  } : null;

  return {
    schemaVersion: 1,
    number: issue.number,
    role,
    state: normalizedState(issue.state),
    title: issue.title ?? "",
    ...(issue.parent ? { parent: issue.parent } : {}),
    labels,
    assignees: sortedUnique(issue.assignees),
    blockedBy: sortedUnique(issue.blockedBy),
    ...(issue.branch ? { branch: issue.branch } : {}),
    ...(issue.disposition ? { disposition: issue.disposition } : {}),
    ...(pullRequest ? { pullRequest } : {}),
  };
}

function childStatus(issue, issuesByNumber, worktrees, integrationBranch, warnings) {
  const openBlockers = issue.blockedBy.filter(
    (number) => issuesByNumber.get(number)?.state !== "closed",
  );
  const issueWorktrees = worktrees.filter((worktree) => worktree.issue === issue.number);
  const pullRequest = issue.pullRequest;

  if (issue.disposition === "cancelled") return { status: "cancelled", openBlockers };
  if (pullRequest?.state === "merged" || issue.state === "closed") {
    return { status: "complete", openBlockers };
  }

  if (pullRequest?.state === "open") {
    if (pullRequest.base !== integrationBranch) {
      warnings.push(
        `Issue #${issue.number} pull request #${pullRequest.number} targets '${pullRequest.base}' instead of '${integrationBranch}'.`,
      );
    }
    if (openBlockers.length > 0) {
      warnings.push(
        `Issue #${issue.number} has an open pull request and open blockers: ${openBlockers.join(", ")}.`,
      );
    }
    return { status: "review", openBlockers };
  }

  if (issue.branch || issueWorktrees.length > 0 || issue.assignees.length > 0) {
    if (openBlockers.length > 0) {
      warnings.push(
        `Issue #${issue.number} has active work and open blockers: ${openBlockers.join(", ")}.`,
      );
    }
    return { status: "in_progress", openBlockers };
  }
  if (openBlockers.length > 0) return { status: "blocked", openBlockers };
  return { status: "ready", openBlockers };
}

function deriveNextAction(featureStatus, children) {
  if (featureStatus === "complete" || featureStatus === "cancelled") {
    return { kind: "none", summary: "No feature action remains." };
  }
  if (featureStatus === "ready_to_finish") {
    return {
      kind: "finish-feature",
      summary: "Review and merge the integration branch into the stable branch.",
    };
  }

  const review = children.find((child) => child.status === "review");
  if (review) {
    return {
      kind: "finish-issue",
      issue: review.number,
      summary: `Review and finish issue #${review.number}.`,
    };
  }
  const active = children.find((child) => child.status === "in_progress");
  if (active) {
    return {
      kind: "continue-issue",
      issue: active.number,
      summary: `Continue issue #${active.number}.`,
    };
  }
  const ready = children.find((child) => child.status === "ready");
  if (ready) {
    return {
      kind: "start-issue",
      issue: ready.number,
      summary: `Start issue #${ready.number}.`,
    };
  }
  return {
    kind: "resolve-blocker",
    summary: "Resolve an open child dependency before more work starts.",
  };
}

export function deriveWorkflowState({
  repositoryRoot,
  repositoryConfig,
  machineConfig,
  githubSnapshot,
  worktreeSnapshot,
  featureNumber,
}) {
  if (githubSnapshot.schemaVersion !== 1) {
    throw new Error(`unsupported GitHub snapshot schemaVersion '${githubSnapshot.schemaVersion}'`);
  }
  if (worktreeSnapshot.schemaVersion !== 1) {
    throw new Error(`unsupported worktree snapshot schemaVersion '${worktreeSnapshot.schemaVersion}'`);
  }

  const issues = (githubSnapshot.issues ?? [])
    .map((issue) => normalizeIssue(issue, repositoryConfig))
    .sort((left, right) => left.number - right.number);
  const issuesByNumber = new Map(issues.map((issue) => [issue.number, issue]));
  const feature = featureNumber
    ? issuesByNumber.get(featureNumber)
    : issues.find((issue) => issue.role === "feature" && issue.state === "open");
  if (!feature || feature.role !== "feature") {
    throw new Error(featureNumber ? `feature issue #${featureNumber} was not found` : "no open feature issue was found");
  }

  const integrationBranch = feature.branch ?? renderPattern(
    repositoryConfig.integrationBranchPattern,
    feature.number,
    feature.title,
  );
  const worktrees = [...(worktreeSnapshot.worktrees ?? [])].sort((left, right) =>
    String(left.id).localeCompare(String(right.id)),
  );
  const warnings = [];
  const children = issues
    .filter((issue) => issue.role === "child" && issue.parent === feature.number)
    .map((issue) => {
      const derived = childStatus(
        issue,
        issuesByNumber,
        worktrees,
        integrationBranch,
        warnings,
      );
      return {
        number: issue.number,
        title: issue.title,
        status: derived.status,
        openBlockers: derived.openBlockers,
        assignees: issue.assignees,
        branch: issue.branch ?? renderPattern(
          repositoryConfig.childBranchPattern,
          issue.number,
          issue.title,
        ),
        worktrees: worktrees
          .filter((worktree) => worktree.issue === issue.number)
          .map((worktree) => ({
            id: worktree.id,
            branch: worktree.branch,
            status: worktree.status ?? "active",
          })),
        ...(issue.pullRequest ? { pullRequest: issue.pullRequest } : {}),
      };
    });

  let featureStatus;
  if (feature.disposition === "cancelled") featureStatus = "cancelled";
  else if (feature.state === "closed") featureStatus = "complete";
  else if (children.length > 0 && children.every((child) =>
    child.status === "complete" || child.status === "cancelled")) {
    featureStatus = "ready_to_finish";
  } else if (children.some((child) =>
    new Set(["in_progress", "review", "complete", "cancelled"]).has(child.status))) {
    featureStatus = "in_progress";
  } else {
    featureStatus = "planned";
  }

  const observed = {
    repositoryConfig,
    machineConfig,
    githubSnapshot: {
      schemaVersion: 1,
      repository: githubSnapshot.repository,
      issues,
    },
    worktreeSnapshot: {
      schemaVersion: 1,
      worktrees,
    },
    featureNumber: feature.number,
  };
  const components = {
    repositoryConfig: fingerprint(repositoryConfig),
    machineConfig: fingerprint(machineConfig),
    github: fingerprint(observed.githubSnapshot),
    worktrees: fingerprint(observed.worktreeSnapshot),
  };

  return {
    schemaVersion: 1,
    repository: {
      root: repositoryRoot,
      slug: githubSnapshot.repository,
      stableBranch: repositoryConfig.stableBranch,
      worktreeManager: machineConfig.worktreeManager,
      worktreeRoot: machineConfig.worktreeRoot,
    },
    feature: {
      number: feature.number,
      title: feature.title,
      status: featureStatus,
      integrationBranch,
    },
    children,
    nextAction: deriveNextAction(featureStatus, children),
    warnings: sortedUnique(warnings),
    freshness: {
      fingerprint: fingerprint(observed),
      components,
    },
  };
}

export async function inspectWorkflow({
  repositoryRoot,
  repositoryConfigPath,
  machineConfigPath,
  githubAdapter,
  worktreeAdapter,
  featureNumber,
}) {
  if (!githubAdapter?.snapshot || !worktreeAdapter?.snapshot) {
    throw new Error("inspection needs GitHub and worktree snapshot adapters");
  }
  const [repository, machine, githubSnapshot, worktreeSnapshot] = await Promise.all([
    readRepositoryConfig(repositoryRoot, repositoryConfigPath),
    readMachineConfig(repositoryRoot, machineConfigPath),
    githubAdapter.snapshot(),
    worktreeAdapter.snapshot(),
  ]);
  return deriveWorkflowState({
    repositoryRoot,
    repositoryConfig: repository.value,
    machineConfig: machine.value,
    githubSnapshot,
    worktreeSnapshot,
    featureNumber,
  });
}
