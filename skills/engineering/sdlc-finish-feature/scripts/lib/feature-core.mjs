import { fingerprint } from "../../../sdlc-workflow/scripts/lib/json.mjs";
import {
  assertReviewEvidence,
  evaluatePullRequestGates,
  runValidationCommands,
} from "../../../sdlc-finish-issue/scripts/lib/finisher.mjs";

function labels(issue) {
  return (issue.labels ?? []).map((label) => typeof label === "string" ? label : label.name);
}

function exactMergedChildPull(child, integrationBranch) {
  return (child.pullRequests ?? []).find((pull) =>
    pull.state === "MERGED" && pull.base === integrationBranch && pull.head === child.branch);
}

export function assertFeatureCandidate(snapshot, config) {
  if (snapshot.invocationBranch !== config.stableBranch) {
    throw new Error(`run feature completion from the stable checkout '${config.stableBranch}'`);
  }
  if (snapshot.parent?.state !== "open" || !labels(snapshot.parent).includes(config.featureLabel)) {
    throw new Error(`feature issue #${snapshot.parent?.number ?? "?"} is not open`);
  }
  if (snapshot.children.length === 0) {
    throw new Error(`feature issue #${snapshot.parent.number} has no child issues`);
  }
  const open = snapshot.children.filter((child) => child.state !== "closed");
  if (open.length > 0) {
    throw new Error(`feature has open children: ${open.map((child) => `#${child.number}`).join(", ")}`);
  }
  for (const child of snapshot.children) {
    if (!labels(child).includes(config.childLabel)) {
      throw new Error(`issue #${child.number} is not labeled '${config.childLabel}'`);
    }
    if (!exactMergedChildPull(child, snapshot.integrationBranch)) {
      throw new Error(
        `child #${child.number} has no merged pull request into '${snapshot.integrationBranch}'`,
      );
    }
  }
  if (!snapshot.integrationWorktree) {
    throw new Error(`integration branch '${snapshot.integrationBranch}' has no local worktree`);
  }
  if (!snapshot.integrationWorktree.clean) {
    throw new Error("integration worktree has uncommitted changes");
  }
  if (!/^[a-f0-9]{40,64}$/.test(snapshot.candidateCommit)) {
    throw new Error("feature candidate commit is not a full Git object ID");
  }
  if (snapshot.finalPullRequests.length > 1) {
    throw new Error(`integration branch '${snapshot.integrationBranch}' has multiple final pull requests`);
  }
  const finalPull = snapshot.finalPullRequests[0];
  if (finalPull && finalPull.state === "CLOSED") {
    throw new Error(`final pull request #${finalPull.number} closed without merging`);
  }
  return snapshot;
}

export function runFeatureValidation(snapshot, config, runner) {
  return runValidationCommands({
    commands: config.featureValidationCommands,
    repositoryRoot: snapshot.integrationWorktree.path,
    candidateCommit: snapshot.candidateCommit,
    runner,
  });
}

function finalBody({ parent, candidateCommit, specificationReview }) {
  return [
    `Closes #${parent}`,
    "",
    "## Integrated specification review",
    "",
    `- Candidate commit: \`${candidateCommit}\``,
    `- Specification review (\`${specificationReview.candidateCommit}\`): ${specificationReview.summary.trim()}`,
    "",
    "This pull request requires explicit user approval before merge.",
    "",
    `<!-- agent-skills:sdlc-feature-review:${candidateCommit} -->`,
  ].join("\n");
}

function closingIssues(body) {
  return [...String(body).matchAll(
    /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#([1-9][0-9]*)\b/gi,
  )].map((match) => Number(match[1]));
}

export function finalPullRequestSubmission(snapshot, specificationReview) {
  const body = finalBody({
    parent: snapshot.parent.number,
    candidateCommit: snapshot.candidateCommit,
    specificationReview,
  });
  if (closingIssues(body).length !== 1 || closingIssues(body)[0] !== snapshot.parent.number) {
    throw new Error("final pull request body must close exactly the parent feature");
  }
  const common = {
    title: snapshot.parent.title,
    base: snapshot.stableBranch,
    head: snapshot.integrationBranch,
    body,
    candidateCommit: snapshot.candidateCommit,
  };
  const existing = snapshot.finalPullRequests[0];
  if (!existing) return { operation: "create", ...common };
  if (existing.head !== snapshot.integrationBranch) {
    throw new Error(`final pull request #${existing.number} uses unexpected head '${existing.head}'`);
  }
  return { operation: "update", number: existing.number, ...common };
}

export async function submitFeature({
  snapshot,
  config,
  validation,
  specificationReview,
  git,
  github,
}) {
  assertFeatureCandidate(snapshot, config);
  if (validation?.status !== "pass" || validation.candidateCommit !== snapshot.candidateCommit) {
    throw new Error("full validation does not cover the feature candidate commit");
  }
  const review = assertReviewEvidence(
    specificationReview,
    "specification",
    snapshot.candidateCommit,
  );
  await git.pushCandidate({
    root: snapshot.integrationWorktree.path,
    branch: snapshot.integrationBranch,
    candidateCommit: snapshot.candidateCommit,
  });
  const pull = await github.submitPullRequest(finalPullRequestSubmission(snapshot, review));
  const approval = {
    operation: "merge-feature",
    feature: snapshot.parent.number,
    pullRequest: pull.number,
    candidateCommit: snapshot.candidateCommit,
    base: snapshot.stableBranch,
    head: snapshot.integrationBranch,
  };
  return {
    schemaVersion: 1,
    status: "awaiting_checks_and_user_approval",
    ...approval,
    candidateId: fingerprint(approval),
  };
}

export function classifyCleanup(snapshot) {
  const mergedBranches = new Set();
  for (const child of snapshot.children) {
    if (exactMergedChildPull(child, snapshot.integrationBranch)) mergedBranches.add(child.branch);
  }
  const finalPull = snapshot.finalPullRequests[0];
  if (finalPull?.state === "OPEN" || finalPull?.state === "MERGED") {
    mergedBranches.add(snapshot.integrationBranch);
  }

  const removable = [];
  const retained = [];
  for (const worktree of snapshot.worktrees) {
    if (worktree.branch === snapshot.stableBranch) {
      retained.push({ ...worktree, reason: "stable-checkout" });
    } else if (!worktree.clean) {
      retained.push({ ...worktree, reason: "dirty-worktree" });
    } else if (!mergedBranches.has(worktree.branch)) {
      retained.push({ ...worktree, reason: "merge-evidence-missing" });
    } else {
      removable.push({ ...worktree, reason: "clean-and-merged" });
    }
  }
  return { removable, retained };
}

export function classifyCancellationCleanup(snapshot) {
  const featureBranches = new Set([
    snapshot.integrationBranch,
    ...snapshot.children.map((child) => child.branch),
  ]);
  const removable = [];
  const retained = [];
  for (const worktree of snapshot.worktrees) {
    if (worktree.branch === snapshot.stableBranch) {
      retained.push({ ...worktree, reason: "stable-checkout" });
    } else if (!featureBranches.has(worktree.branch)) {
      retained.push({ ...worktree, reason: "not-feature-worktree" });
    } else if (!worktree.clean) {
      retained.push({ ...worktree, reason: "dirty-worktree" });
    } else if (!worktree.mergedToStable) {
      retained.push({ ...worktree, reason: "not-merged-to-stable" });
    } else {
      removable.push({ ...worktree, reason: "clean-and-merged-to-stable" });
    }
  }
  return { removable, retained };
}

function planContent(snapshot, cleanup, evidence, mergeMethod) {
  const pull = snapshot.finalPullRequests[0];
  return {
    schemaVersion: 1,
    operation: "merge-feature",
    feature: snapshot.parent.number,
    pullRequest: pull.number,
    candidateCommit: snapshot.candidateCommit,
    mergeMethod,
    freshness: fingerprint(snapshot),
    evidence,
    cleanup,
  };
}

export function createFeatureMergePlan(snapshot, config, evidence) {
  assertFeatureCandidate(snapshot, config);
  if (evidence?.validation?.status !== "pass" ||
      evidence.validation.candidateCommit !== snapshot.candidateCommit) {
    throw new Error("full validation does not cover the feature candidate commit");
  }
  const specificationReview = assertReviewEvidence(
    evidence?.specificationReview,
    "specification",
    snapshot.candidateCommit,
  );
  const pull = snapshot.finalPullRequests[0];
  if (!pull) throw new Error("feature has no final pull request");
  const gate = evaluatePullRequestGates(pull, {
    base: snapshot.stableBranch,
    head: snapshot.integrationBranch,
    candidateCommit: snapshot.candidateCommit,
  });
  if (gate.status !== "ready") {
    throw new Error(`final pull request #${pull.number} is not ready: ${gate.reason ?? gate.status}`);
  }
  const content = planContent(snapshot, classifyCleanup(snapshot), {
    validation: evidence.validation,
    specificationReview,
  }, config.featureMergeMethod);
  return { ...content, planId: fingerprint(content) };
}

export async function applyFeatureMergePlan({
  plan,
  approved,
  currentSnapshot,
  config,
  github,
  cleanup,
}) {
  if (approved !== plan.planId) throw new Error("final merge needs approval for the exact planId");
  const expected = { ...plan };
  delete expected.planId;
  if (fingerprint(expected) !== plan.planId) throw new Error("final merge plan content changed");
  if (fingerprint(currentSnapshot) !== plan.freshness) {
    throw new Error("final merge plan is stale; create and approve a new plan");
  }
  const currentPlan = createFeatureMergePlan(currentSnapshot, config, plan.evidence);
  if (currentPlan.planId !== plan.planId) {
    throw new Error("final merge plan no longer matches live state");
  }
  const merged = await github.mergePullRequest({
    number: plan.pullRequest,
    method: plan.mergeMethod,
    candidateCommit: plan.candidateCommit,
  });
  if (!merged.merged) throw new Error(`final pull request #${plan.pullRequest} did not merge`);
  await github.closeIssue(plan.feature);

  const removed = [];
  const retained = [...plan.cleanup.retained];
  for (const worktree of plan.cleanup.removable) {
    try {
      await cleanup.remove(worktree);
      removed.push(worktree);
    } catch (error) {
      retained.push({ ...worktree, reason: `cleanup-failed: ${error.message}` });
    }
  }
  return {
    schemaVersion: 1,
    status: "merged",
    feature: plan.feature,
    pullRequest: plan.pullRequest,
    cleanup: { removed, retained },
  };
}

export function createCancellationPlan(snapshot) {
  const actions = [];
  for (const pull of [
    ...snapshot.children.flatMap((child) => child.pullRequests ?? []),
    ...snapshot.finalPullRequests,
  ]) {
    if (pull.state === "OPEN") {
      actions.push({ type: "close-pull-request", number: pull.number });
    }
  }
  for (const child of snapshot.children) {
    if (child.state === "open") actions.push({ type: "close-issue", number: child.number });
  }
  if (snapshot.parent.state === "open") {
    actions.push({ type: "close-issue", number: snapshot.parent.number });
  }
  const cleanup = classifyCancellationCleanup(snapshot);
  const content = {
    schemaVersion: 1,
    operation: "cancel-feature",
    feature: snapshot.parent.number,
    freshness: fingerprint(snapshot),
    actions,
    cleanup,
  };
  return { ...content, planId: fingerprint(content) };
}

export async function applyCancellationPlan({
  plan,
  approved,
  currentSnapshot,
  github,
  cleanup,
}) {
  if (approved !== plan.planId) throw new Error("cancellation needs approval for the exact planId");
  const expected = { ...plan };
  delete expected.planId;
  if (fingerprint(expected) !== plan.planId) throw new Error("cancellation plan content changed");
  if (fingerprint(currentSnapshot) !== plan.freshness) {
    throw new Error("cancellation plan is stale; create and approve a new plan");
  }
  if (createCancellationPlan(currentSnapshot).planId !== plan.planId) {
    throw new Error("cancellation plan no longer matches live state");
  }
  const receipts = [];
  for (const action of plan.actions) {
    if (action.type === "close-pull-request") {
      receipts.push(await github.closePullRequest(action.number));
    } else if (action.type === "close-issue") {
      receipts.push(await github.closeIssue(action.number, "not planned"));
    } else {
      throw new Error(`unsupported cancellation action '${action.type}'`);
    }
  }
  const removed = [];
  const retained = [...plan.cleanup.retained];
  for (const worktree of plan.cleanup.removable) {
    try {
      await cleanup.remove(worktree);
      removed.push(worktree);
    } catch (error) {
      retained.push({ ...worktree, reason: `cleanup-failed: ${error.message}` });
    }
  }
  return {
    schemaVersion: 1,
    status: "cancelled",
    feature: plan.feature,
    receipts,
    cleanup: { removed, retained },
  };
}
