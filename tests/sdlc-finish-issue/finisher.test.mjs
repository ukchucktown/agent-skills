import assert from "node:assert/strict";
import test from "node:test";

import {
  assertFinishCandidate,
  assertReviewEvidence,
  evaluatePullRequestGates,
  finishIssue,
  pullRequestSubmission,
  runValidationCommands,
} from "../../skills/engineering/sdlc-finish-issue/scripts/lib/finisher.mjs";

const candidateCommit = "a".repeat(40);

function config(overrides = {}) {
  return {
    stableBranch: "main",
    childLabel: "sdlc:child",
    featureLabel: "sdlc:feature",
    childValidationCommands: [],
    autoMergeChildPullRequests: true,
    closeChildOnIntegrationMerge: true,
    childMergeMethod: "squash",
    ...overrides,
  };
}

function snapshot(overrides = {}) {
  return {
    schemaVersion: 1,
    repository: "octo/widgets",
    issue: {
      number: 7,
      state: "open",
      title: "Finish one issue",
      labels: ["sdlc:child"],
    },
    parent: {
      number: 1,
      state: "open",
      title: "Large feature",
      labels: ["sdlc:feature"],
    },
    blockers: [{ number: 6, state: "closed" }],
    branch: "feat/issue-7-finish-issue",
    integrationBranch: "integration/issue-1-large-feature",
    integrationBranchExists: true,
    currentBranch: "feat/issue-7-finish-issue",
    candidateCommit,
    clean: true,
    pullRequests: [],
    ...overrides,
  };
}

function review(axis, overrides = {}) {
  return {
    schemaVersion: 1,
    axis,
    candidateCommit,
    verdict: "pass",
    summary: `${axis} review passed.`,
    ...overrides,
  };
}

test("candidate validation rejects dirty work and stable-branch pull requests", () => {
  assert.throws(
    () => assertFinishCandidate(snapshot({ clean: false }), config()),
    /uncommitted changes/,
  );
  assert.throws(
    () => assertFinishCandidate(snapshot({ integrationBranch: "main" }), config()),
    /stable branch/,
  );
});

test("review evidence is bound to one axis and candidate commit", () => {
  assert.deepEqual(
    assertReviewEvidence(review("standards"), "standards", candidateCommit),
    review("standards"),
  );
  assert.throws(
    () => assertReviewEvidence(
      review("standards", { candidateCommit: "b".repeat(40) }),
      "standards",
      candidateCommit,
    ),
    /not candidate/,
  );
  assert.throws(
    () => assertReviewEvidence(review("standards"), "specification", candidateCommit),
    /expected specification/,
  );
});

test("validation commands use structured arguments without a shell", () => {
  const calls = [];
  const commands = [{ executable: "npm", args: ["test", "--", "--unit"] }];
  const result = runValidationCommands({
    commands,
    repositoryRoot: "/tmp/widgets",
    candidateCommit,
    runner(executable, args, options) {
      calls.push({ executable, args, options });
    },
  });
  assert.equal(result.candidateCommit, candidateCommit);
  assert.equal(result.status, "pass");
  assert.equal(calls[0].executable, "npm");
  assert.deepEqual(calls[0].args, ["test", "--", "--unit"]);
  assert.equal(calls[0].options.shell, false);
});

test("submission targets the recorded integration branch and closes only its child", () => {
  const submission = pullRequestSubmission(snapshot(), {
    standards: review("standards"),
    specification: review("specification"),
  });
  assert.equal(submission.operation, "create");
  assert.equal(submission.base, "integration/issue-1-large-feature");
  assert.equal(submission.head, "feat/issue-7-finish-issue");
  assert.match(submission.body, /^Closes #7\n/);
  assert.doesNotMatch(submission.body, /Closes #1/);
  assert.match(submission.body, new RegExp(candidateCommit));

  const updated = pullRequestSubmission(snapshot({
    pullRequests: [{
      number: 23,
      state: "OPEN",
      base: "wrong-base",
      head: "feat/issue-7-finish-issue",
    }],
  }), {
    standards: review("standards"),
    specification: review("specification"),
  });
  assert.equal(updated.operation, "update");
  assert.equal(updated.number, 23);
  assert.equal(updated.base, "integration/issue-1-large-feature");
});

test("GitHub gates reject a changed candidate and honor checks and reviews", () => {
  const expected = {
    base: "integration/issue-1-large-feature",
    head: "feat/issue-7-finish-issue",
    candidateCommit,
  };
  const pull = {
    number: 23,
    state: "OPEN",
    base: expected.base,
    head: expected.head,
    headSha: candidateCommit,
    checks: [{ status: "COMPLETED", conclusion: "SUCCESS" }],
    reviewDecision: "APPROVED",
    mergeable: "MERGEABLE",
    isDraft: false,
  };
  assert.deepEqual(evaluatePullRequestGates(pull, expected), { status: "ready" });
  assert.equal(
    evaluatePullRequestGates({ ...pull, headSha: "b".repeat(40) }, expected).reason,
    "candidate-commit-changed",
  );
  assert.equal(
    evaluatePullRequestGates({ ...pull, checks: [{ status: "IN_PROGRESS" }] }, expected).reason,
    "checks-pending",
  );
  assert.equal(
    evaluatePullRequestGates({ ...pull, reviewDecision: "REVIEW_REQUIRED" }, expected).reason,
    "review-required",
  );
});

test("a fully gated child merges with the configured method and closes its issue", async () => {
  const calls = [];
  const current = snapshot();
  const pull = {
    number: 23,
    state: "OPEN",
    base: current.integrationBranch,
    head: current.branch,
    headSha: candidateCommit,
    checks: [{ status: "COMPLETED", conclusion: "SUCCESS" }],
    reviewDecision: "APPROVED",
    mergeable: "MERGEABLE",
    isDraft: false,
  };
  const result = await finishIssue({
    snapshot: current,
    config: config(),
    validation: { status: "pass", candidateCommit },
    standardsReview: review("standards"),
    specificationReview: review("specification"),
    git: {
      async pushCandidate(parameters) { calls.push(["push", parameters]); },
    },
    github: {
      async submitPullRequest(submission) {
        calls.push(["submit", submission]);
        return { number: 23 };
      },
      async waitForGates() { calls.push(["wait"]); return pull; },
      async mergePullRequest(parameters) {
        calls.push(["merge", parameters]);
        return { merged: true };
      },
      async closeIssue(number) { calls.push(["close", number]); },
    },
  });
  assert.equal(result.status, "merged");
  assert.equal(result.mergeMethod, "squash");
  assert.deepEqual(calls.map(([operation]) => operation), ["push", "submit", "wait", "merge", "close"]);
  assert.equal(calls[3][1].candidateCommit, candidateCommit);
});

test("disabled child auto-merge stops after authoritative gates", async () => {
  const current = snapshot();
  let merged = false;
  const result = await finishIssue({
    snapshot: current,
    config: config({ autoMergeChildPullRequests: false }),
    validation: { status: "pass", candidateCommit },
    standardsReview: review("standards"),
    specificationReview: review("specification"),
    git: { async pushCandidate() {} },
    github: {
      async submitPullRequest() { return { number: 23 }; },
      async waitForGates() {
        return {
          number: 23,
          state: "OPEN",
          base: current.integrationBranch,
          head: current.branch,
          headSha: candidateCommit,
          checks: [],
          reviewDecision: "",
          mergeable: "MERGEABLE",
          isDraft: false,
        };
      },
      async mergePullRequest() { merged = true; return { merged: true }; },
    },
  });
  assert.equal(result.status, "ready_for_merge");
  assert.equal(merged, false);
});

test("a retry closes an issue whose exact candidate pull request already merged", async () => {
  let closed = null;
  const result = await finishIssue({
    snapshot: snapshot({
      pullRequests: [{
        number: 23,
        state: "MERGED",
        base: "integration/issue-1-large-feature",
        head: "feat/issue-7-finish-issue",
        headSha: candidateCommit,
      }],
    }),
    config: config(),
    validation: { status: "pass", candidateCommit },
    standardsReview: review("standards"),
    specificationReview: review("specification"),
    git: {
      async pushCandidate() { throw new Error("merged retry pushed a branch"); },
    },
    github: {
      async closeIssue(number) { closed = number; },
    },
  });
  assert.equal(result.status, "merged");
  assert.equal(closed, 7);
});

test("validation and reviews must cover the same current commit", async () => {
  await assert.rejects(
    () => finishIssue({
      snapshot: snapshot(),
      config: config(),
      validation: { status: "pass", candidateCommit: "b".repeat(40) },
      standardsReview: review("standards"),
      specificationReview: review("specification"),
      git: {},
      github: {},
    }),
    /validation does not cover/,
  );
});
