import { execFileSync } from "node:child_process";

function names(values = []) {
  return values.map((value) => typeof value === "string" ? value : value.name);
}

function closingIssues(body) {
  return [...String(body ?? "").matchAll(
    /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#([1-9][0-9]*)\b/gi,
  )].map((match) => Number(match[1]));
}

export function assertReviewEvidence(review, axis, candidateCommit) {
  if (!review || review.schemaVersion !== 1) {
    throw new Error(`${axis} review needs schemaVersion 1`);
  }
  if (review.axis !== axis) throw new Error(`expected ${axis} review evidence`);
  if (review.candidateCommit !== candidateCommit) {
    throw new Error(
      `${axis} review covers '${review.candidateCommit ?? "unknown"}', not candidate '${candidateCommit}'`,
    );
  }
  if (review.verdict !== "pass") throw new Error(`${axis} review did not pass`);
  if (typeof review.summary !== "string" || !review.summary.trim()) {
    throw new Error(`${axis} review needs a summary`);
  }
  return structuredClone(review);
}

export function assertFinishCandidate(snapshot, config) {
  if (snapshot.issue?.state !== "open") {
    throw new Error(`child issue #${snapshot.issue?.number ?? "?"} is not open`);
  }
  if (!names(snapshot.issue.labels).includes(config.childLabel)) {
    throw new Error(`issue #${snapshot.issue.number} is not labeled '${config.childLabel}'`);
  }
  if (snapshot.parent?.state !== "open" ||
      !names(snapshot.parent.labels).includes(config.featureLabel)) {
    throw new Error(`issue #${snapshot.issue.number} has no open configured feature parent`);
  }
  const openBlockers = snapshot.blockers.filter((blocker) => blocker.state !== "closed");
  if (openBlockers.length > 0) {
    throw new Error(
      `issue #${snapshot.issue.number} has open blockers: ${openBlockers.map((item) => `#${item.number}`).join(", ")}`,
    );
  }
  if (!snapshot.integrationBranchExists) {
    throw new Error(`integration branch '${snapshot.integrationBranch}' does not exist`);
  }
  if (snapshot.integrationBranch === config.stableBranch) {
    throw new Error("sdlc-finish-issue cannot merge a pull request into the stable branch");
  }
  if (snapshot.currentBranch !== snapshot.branch) {
    throw new Error(
      `current branch '${snapshot.currentBranch}' does not match recorded branch '${snapshot.branch}'`,
    );
  }
  if (!snapshot.clean) throw new Error("candidate worktree has uncommitted changes");
  if (!/^[a-f0-9]{40,64}$/.test(snapshot.candidateCommit)) {
    throw new Error("candidate commit is not a full Git object ID");
  }
  if (snapshot.pullRequests.length > 1) {
    throw new Error(`branch '${snapshot.branch}' has multiple pull requests`);
  }
  const pullRequest = snapshot.pullRequests[0];
  if (pullRequest && pullRequest.state === "CLOSED") {
    throw new Error(`pull request #${pullRequest.number} closed without merging`);
  }
  return snapshot;
}

export function runValidationCommands({
  commands,
  repositoryRoot,
  candidateCommit,
  runner = execFileSync,
}) {
  const completed = [];
  for (const command of commands) {
    runner(command.executable, command.args, {
      cwd: repositoryRoot,
      encoding: "utf8",
      stdio: "inherit",
      shell: false,
    });
    completed.push({ executable: command.executable, args: [...command.args] });
  }
  return {
    schemaVersion: 1,
    candidateCommit,
    status: "pass",
    commands: completed,
  };
}

export function pullRequestBody({ issue, candidateCommit, standardsReview, specificationReview }) {
  return [
    `Closes #${issue}`,
    "",
    "## Review evidence",
    "",
    `- Candidate commit: \`${candidateCommit}\``,
    `- Standards review (\`${standardsReview.candidateCommit}\`): ${standardsReview.summary.trim()}`,
    `- Specification review (\`${specificationReview.candidateCommit}\`): ${specificationReview.summary.trim()}`,
    "",
    `<!-- agent-skills:sdlc-review:${candidateCommit} -->`,
  ].join("\n");
}

export function pullRequestSubmission(snapshot, reviews) {
  const body = pullRequestBody({
    issue: snapshot.issue.number,
    candidateCommit: snapshot.candidateCommit,
    standardsReview: reviews.standards,
    specificationReview: reviews.specification,
  });
  if (closingIssues(body).length !== 1 || closingIssues(body)[0] !== snapshot.issue.number) {
    throw new Error("generated pull request body must close exactly the child issue");
  }
  const common = {
    issue: snapshot.issue.number,
    title: snapshot.issue.title,
    base: snapshot.integrationBranch,
    head: snapshot.branch,
    candidateCommit: snapshot.candidateCommit,
    body,
  };
  const existing = snapshot.pullRequests[0];
  if (!existing) return { operation: "create", ...common };
  if (existing.head !== snapshot.branch) {
    throw new Error(`pull request #${existing.number} uses unexpected head '${existing.head}'`);
  }
  return { operation: "update", number: existing.number, ...common };
}

function checkState(check) {
  const conclusion = String(check.conclusion ?? "").toUpperCase();
  const status = String(check.status ?? "").toUpperCase();
  if (status && status !== "COMPLETED") return "pending";
  if (!conclusion || new Set(["PENDING", "QUEUED", "IN_PROGRESS", "WAITING"]).has(conclusion)) {
    return "pending";
  }
  if (new Set(["SUCCESS", "SKIPPED", "NEUTRAL"]).has(conclusion)) return "pass";
  return "fail";
}

export function evaluatePullRequestGates(pullRequest, expected) {
  if (!pullRequest) return { status: "waiting", reason: "pull-request-missing" };
  if (pullRequest.base !== expected.base || pullRequest.head !== expected.head) {
    return { status: "failed", reason: "pull-request-target-changed" };
  }
  if (pullRequest.headSha !== expected.candidateCommit) {
    return { status: "failed", reason: "candidate-commit-changed" };
  }
  if (pullRequest.state === "MERGED") return { status: "merged" };
  if (pullRequest.state !== "OPEN") return { status: "failed", reason: "pull-request-closed" };
  if (pullRequest.isDraft) return { status: "waiting", reason: "pull-request-draft" };
  const checks = (pullRequest.checks ?? []).map(checkState);
  if (checks.includes("fail")) return { status: "failed", reason: "checks-failed" };
  if (checks.includes("pending")) return { status: "waiting", reason: "checks-pending" };
  const review = String(pullRequest.reviewDecision ?? "").toUpperCase();
  if (review === "CHANGES_REQUESTED") {
    return { status: "failed", reason: "changes-requested" };
  }
  if (review === "REVIEW_REQUIRED") {
    return { status: "waiting", reason: "review-required" };
  }
  if (String(pullRequest.mergeable ?? "").toUpperCase() === "CONFLICTING") {
    return { status: "failed", reason: "merge-conflict" };
  }
  return { status: "ready" };
}

export async function finishIssue({
  snapshot,
  config,
  validation,
  standardsReview,
  specificationReview,
  git,
  github,
}) {
  assertFinishCandidate(snapshot, config);
  if (validation?.status !== "pass" || validation.candidateCommit !== snapshot.candidateCommit) {
    throw new Error("validation does not cover the candidate commit");
  }
  const reviews = {
    standards: assertReviewEvidence(standardsReview, "standards", snapshot.candidateCommit),
    specification: assertReviewEvidence(
      specificationReview,
      "specification",
      snapshot.candidateCommit,
    ),
  };
  const existing = snapshot.pullRequests[0];
  const expected = {
    base: snapshot.integrationBranch,
    head: snapshot.branch,
    candidateCommit: snapshot.candidateCommit,
  };
  if (existing && evaluatePullRequestGates(existing, expected).status === "merged") {
    if (config.closeChildOnIntegrationMerge) await github.closeIssue(snapshot.issue.number);
    return {
      schemaVersion: 1,
      status: "merged",
      pullRequest: existing.number,
      issue: snapshot.issue.number,
      candidateCommit: snapshot.candidateCommit,
      mergeMethod: config.childMergeMethod,
    };
  }
  const submission = pullRequestSubmission(snapshot, reviews);

  await git.pushCandidate({
    branch: snapshot.branch,
    candidateCommit: snapshot.candidateCommit,
  });
  const submitted = await github.submitPullRequest(submission);
  const gated = await github.waitForGates({
    number: submitted.number,
    base: snapshot.integrationBranch,
    head: snapshot.branch,
    candidateCommit: snapshot.candidateCommit,
  });
  const gate = evaluatePullRequestGates(gated, expected);
  if (gate.status === "merged") {
    return { schemaVersion: 1, status: "merged", pullRequest: gated.number, issue: snapshot.issue.number };
  }
  if (gate.status !== "ready") {
    throw new Error(`pull request #${gated.number} is not mergeable: ${gate.reason}`);
  }
  if (!config.autoMergeChildPullRequests) {
    return {
      schemaVersion: 1,
      status: "ready_for_merge",
      pullRequest: gated.number,
      issue: snapshot.issue.number,
      candidateCommit: snapshot.candidateCommit,
    };
  }

  const merged = await github.mergePullRequest({
    number: gated.number,
    method: config.childMergeMethod,
    candidateCommit: snapshot.candidateCommit,
  });
  if (!merged.merged) throw new Error(`pull request #${gated.number} did not merge`);
  if (config.closeChildOnIntegrationMerge) await github.closeIssue(snapshot.issue.number);
  return {
    schemaVersion: 1,
    status: "merged",
    pullRequest: gated.number,
    issue: snapshot.issue.number,
    candidateCommit: snapshot.candidateCommit,
    mergeMethod: config.childMergeMethod,
  };
}
