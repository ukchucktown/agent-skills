import assert from "node:assert/strict";
import test from "node:test";

import {
  applyCancellationPlan,
  applyFeatureMergePlan,
  assertFeatureCandidate,
  classifyCancellationCleanup,
  classifyCleanup,
  createCancellationPlan,
  createFeatureMergePlan,
  finalPullRequestSubmission,
  submitFeature,
} from "../../skills/engineering/sdlc-finish-feature/scripts/lib/feature-core.mjs";

const candidateCommit = "c".repeat(40);

function config(overrides = {}) {
  return {
    stableBranch: "main",
    featureLabel: "sdlc:feature",
    childLabel: "sdlc:child",
    featureValidationCommands: [],
    featureMergeMethod: "merge",
    ...overrides,
  };
}

function review(overrides = {}) {
  return {
    schemaVersion: 1,
    axis: "specification",
    candidateCommit,
    verdict: "pass",
    summary: "The integrated change satisfies the parent specification.",
    ...overrides,
  };
}

function readyPull(overrides = {}) {
  return {
    number: 31,
    state: "OPEN",
    base: "main",
    head: "integration/issue-1-large-feature",
    headSha: candidateCommit,
    checks: [{ status: "COMPLETED", conclusion: "SUCCESS" }],
    reviewDecision: "APPROVED",
    mergeable: "MERGEABLE",
    isDraft: false,
    ...overrides,
  };
}

function snapshot(overrides = {}) {
  const integrationBranch = "integration/issue-1-large-feature";
  return {
    schemaVersion: 1,
    repository: "octo/widgets",
    stableBranch: "main",
    invocationBranch: "main",
    parent: {
      number: 1,
      state: "open",
      title: "Large feature",
      labels: ["sdlc:feature"],
    },
    children: [{
      number: 2,
      state: "closed",
      title: "Child",
      labels: ["sdlc:child"],
      branch: "feat/issue-2-child",
      pullRequests: [{
        number: 22,
        state: "MERGED",
        base: integrationBranch,
        head: "feat/issue-2-child",
        headSha: "a".repeat(40),
      }],
    }],
    integrationBranch,
    integrationWorktree: {
      path: "/worktrees/widgets/integration",
      branch: integrationBranch,
      clean: true,
      mergedToStable: false,
    },
    candidateCommit,
    finalPullRequests: [readyPull()],
    worktrees: [
      { path: "/checkout/widgets", branch: "main", clean: true, mergedToStable: true },
      { path: "/worktrees/widgets/child", branch: "feat/issue-2-child", clean: true, mergedToStable: false },
      { path: "/worktrees/widgets/integration", branch: integrationBranch, clean: true, mergedToStable: false },
      { path: "/worktrees/widgets/dirty", branch: "feat/issue-9-dirty", clean: false, mergedToStable: false },
      { path: "/worktrees/widgets/unknown", branch: "fix/unknown", clean: true, mergedToStable: false },
    ],
    ...overrides,
  };
}

function evidence() {
  return {
    validation: { schemaVersion: 1, status: "pass", candidateCommit, commands: [] },
    specificationReview: review(),
  };
}

test("feature completion refuses open children and missing child merge evidence", () => {
  const open = snapshot();
  open.children[0].state = "open";
  assert.throws(() => assertFeatureCandidate(open, config()), /open children: #2/);

  const unmerged = snapshot();
  unmerged.children[0].pullRequests[0].state = "CLOSED";
  assert.throws(() => assertFeatureCandidate(unmerged, config()), /no merged pull request/);
});

test("the final pull request targets stable and closes only the parent", () => {
  const current = snapshot({ finalPullRequests: [] });
  const submission = finalPullRequestSubmission(current, review());
  assert.equal(submission.operation, "create");
  assert.equal(submission.base, "main");
  assert.equal(submission.head, "integration/issue-1-large-feature");
  assert.match(submission.body, /^Closes #1\n/);
  assert.doesNotMatch(submission.body, /Closes #2/);
  assert.match(submission.body, /explicit user approval/);
});

test("submitting a feature validates and reviews the exact candidate without merging", async () => {
  const current = snapshot({ finalPullRequests: [] });
  const calls = [];
  const result = await submitFeature({
    snapshot: current,
    config: config(),
    validation: evidence().validation,
    specificationReview: review(),
    git: {
      async pushCandidate(parameters) { calls.push(["push", parameters]); },
    },
    github: {
      async submitPullRequest(parameters) {
        calls.push(["submit", parameters]);
        return { number: 31 };
      },
    },
  });
  assert.equal(result.status, "awaiting_checks_and_user_approval");
  assert.equal(result.pullRequest, 31);
  assert.deepEqual(calls.map(([operation]) => operation), ["push", "submit"]);
  assert.equal(result.candidateCommit, candidateCommit);
});

test("the final merge plan requires complete evidence and authoritative gates", () => {
  assert.throws(
    () => createFeatureMergePlan(snapshot(), config(), {
      ...evidence(),
      validation: { status: "fail", candidateCommit },
    }),
    /full validation/,
  );
  assert.throws(
    () => createFeatureMergePlan(snapshot({
      finalPullRequests: [readyPull({ checks: [{ status: "IN_PROGRESS" }] })],
    }), config(), evidence()),
    /checks-pending/,
  );
  const plan = createFeatureMergePlan(snapshot(), config(), evidence());
  assert.equal(plan.operation, "merge-feature");
  assert.equal(plan.candidateCommit, candidateCommit);
  assert.match(plan.planId, /^[a-f0-9]{64}$/);
});

test("final cleanup removes only clean branches with complete merge evidence", () => {
  const result = classifyCleanup(snapshot());
  assert.deepEqual(
    result.removable.map((worktree) => worktree.branch).sort(),
    ["feat/issue-2-child", "integration/issue-1-large-feature"],
  );
  assert.deepEqual(
    result.retained.map((worktree) => [worktree.branch, worktree.reason]),
    [
      ["main", "stable-checkout"],
      ["feat/issue-9-dirty", "dirty-worktree"],
      ["fix/unknown", "merge-evidence-missing"],
    ],
  );
});

test("the exact approved final plan merges, closes, and reports cleanup", async () => {
  const current = snapshot();
  const plan = createFeatureMergePlan(current, config(), evidence());
  const calls = [];
  const result = await applyFeatureMergePlan({
    plan,
    approved: plan.planId,
    currentSnapshot: current,
    config: config(),
    github: {
      async mergePullRequest(parameters) {
        calls.push(["merge", parameters]);
        return { merged: true };
      },
      async closeIssue(number) { calls.push(["close", number]); },
    },
    cleanup: {
      async remove(worktree) { calls.push(["remove", worktree.branch]); },
    },
  });
  assert.equal(result.status, "merged");
  assert.deepEqual(calls.map(([operation]) => operation), ["merge", "close", "remove", "remove"]);
  assert.equal(result.cleanup.removed.length, 2);

  await assert.rejects(
    () => applyFeatureMergePlan({
      plan,
      approved: "wrong",
      currentSnapshot: current,
      config: config(),
      github: {},
      cleanup: {},
    }),
    /exact planId/,
  );
});

test("cancellation shows every closure and keeps unmerged or dirty work", async () => {
  const current = snapshot({
    parent: { number: 1, state: "open", title: "Large feature", labels: ["sdlc:feature"] },
    children: [{
      number: 2,
      state: "open",
      title: "Child",
      labels: ["sdlc:child"],
      branch: "feat/issue-2-child",
      pullRequests: [readyPull({ number: 22, base: "integration/issue-1-large-feature", head: "feat/issue-2-child" })],
    }],
  });
  const cleanup = classifyCancellationCleanup(current);
  assert.equal(cleanup.removable.length, 0);
  assert.ok(cleanup.retained.some((worktree) => worktree.reason === "not-feature-worktree"));
  assert.ok(cleanup.retained.some((worktree) => worktree.reason === "not-merged-to-stable"));

  const plan = createCancellationPlan(current);
  assert.deepEqual(plan.actions, [
    { type: "close-pull-request", number: 22 },
    { type: "close-pull-request", number: 31 },
    { type: "close-issue", number: 2 },
    { type: "close-issue", number: 1 },
  ]);

  const calls = [];
  const result = await applyCancellationPlan({
    plan,
    approved: plan.planId,
    currentSnapshot: current,
    github: {
      async closePullRequest(number) { calls.push(["pull", number]); return { number }; },
      async closeIssue(number, reason) { calls.push(["issue", number, reason]); return { number }; },
    },
    cleanup: {
      async remove() { throw new Error("cancellation removed retained work"); },
    },
  });
  assert.equal(result.status, "cancelled");
  assert.deepEqual(calls, [
    ["pull", 22],
    ["pull", 31],
    ["issue", 2, "not planned"],
    ["issue", 1, "not planned"],
  ]);
  assert.equal(result.cleanup.removed.length, 0);
});

test("cancellation rejects unapproved and stale plans before side effects", async () => {
  const current = snapshot();
  const plan = createCancellationPlan(current);
  let called = false;
  await assert.rejects(
    () => applyCancellationPlan({
      plan,
      approved: "wrong",
      currentSnapshot: current,
      github: { async closeIssue() { called = true; } },
      cleanup: {},
    }),
    /exact planId/,
  );
  assert.equal(called, false);

  await assert.rejects(
    () => applyCancellationPlan({
      plan,
      approved: plan.planId,
      currentSnapshot: { ...current, candidateCommit: "d".repeat(40) },
      github: { async closeIssue() { called = true; } },
      cleanup: {},
    }),
    /stale/,
  );
  assert.equal(called, false);
});
