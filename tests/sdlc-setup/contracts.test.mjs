import assert from "node:assert/strict";
import test from "node:test";

import {
  branchMatch,
  classifyPullRequest,
  closeMergedChild,
  parseRepositoryConfig,
  runValidationCommands,
  validatePullRequest,
} from "../../skills/engineering/sdlc-setup/templates/.github/scripts/sdlc-contract-lib.mjs";
import { renderRepositoryDocument } from "../../skills/engineering/sdlc-setup/scripts/lib/setup-core.mjs";

const config = {
  schemaVersion: 1,
  provider: "github",
  stableBranch: "main",
  integrationBranchPattern: "integration/issue-{issue}-{slug}",
  childBranchPattern: "feat/issue-{issue}-{slug}",
  worktreeRetention: "feature",
  closeChildOnIntegrationMerge: true,
  autoMergeChildPullRequests: true,
  childMergeMethod: "merge",
  featureMergeMethod: "merge",
  childValidationCommands: [{ executable: "npm", args: ["test", "--", "--unit"] }],
  featureValidationCommands: [{ executable: "npm", args: ["test"] }],
  finalMergeApproval: "required",
  featureLabel: "sdlc:feature",
  childLabel: "sdlc:child",
  readyLabel: "ready-for-agent",
};

function event({
  base = "integration/issue-1-large-feature",
  head = "feat/issue-2-foundation",
  body = "Closes #2",
  merged = false,
  action = "opened",
} = {}) {
  return {
    action,
    repository: { full_name: "example/widgets" },
    pull_request: {
      body,
      merged,
      base: { ref: base, sha: "base-sha" },
      head: { ref: head, sha: "head-sha" },
    },
  };
}

class FakeApi {
  constructor({ blockers = [], children = [] } = {}) {
    this.issues = new Map([
      [1, { number: 1, state: "open", labels: [{ name: "sdlc:feature" }] }],
      [2, { number: 2, state: "open", labels: [{ name: "sdlc:child" }] }],
    ]);
    this.parents = new Map([[2, { number: 1 }]]);
    this.blockers = blockers;
    this.children = children;
    this.closed = [];
  }

  async issue(number) { return structuredClone(this.issues.get(number)); }
  async parent(number) { return structuredClone(this.parents.get(number)); }
  async blockedBy() { return structuredClone(this.blockers); }
  async subIssues() { return structuredClone(this.children); }
  async closeIssue(number) {
    this.closed.push(number);
    this.issues.get(number).state = "closed";
  }
}

test("branch classification affects only configured integration contracts", () => {
  assert.equal(
    branchMatch(config.integrationBranchPattern, "integration/issue-148-session-setup").groups.issue,
    "148",
  );
  assert.deepEqual(
    classifyPullRequest(event().pull_request, config),
    { type: "child", featureNumber: 1 },
  );
  assert.deepEqual(
    classifyPullRequest(event({ base: "main", head: "integration/issue-1-large-feature" }).pull_request, config),
    { type: "feature", featureNumber: 1 },
  );
  assert.deepEqual(
    classifyPullRequest(event({ base: "main", head: "fix/small-bug" }).pull_request, config),
    { type: "ordinary" },
  );
});

test("a child contract needs one child, the correct parent, and closed blockers", async () => {
  const api = new FakeApi({ blockers: [{ number: 9, state: "closed" }] });
  const result = await validatePullRequest({ event: event(), config, api });
  assert.equal(result.profile, "child");
  assert.equal(result.issue, 2);

  api.blockers = [{ number: 9, state: "open" }];
  await assert.rejects(
    validatePullRequest({ event: event(), config, api }),
    /open blockers: #9/,
  );
  api.blockers = [];
  api.parents.set(2, { number: 99 });
  await assert.rejects(
    validatePullRequest({ event: event(), config, api }),
    /belongs to #99, not #1/,
  );
  api.parents.set(2, { number: 1 });
  await assert.rejects(
    validatePullRequest({ event: event({ body: "Closes #2 and fixes #3" }), config, api }),
    /must close exactly one issue/,
  );
});

test("a final contract needs the correct parent and complete child issues", async () => {
  const api = new FakeApi({
    children: [{ number: 2, state: "closed", labels: [{ name: "sdlc:child" }] }],
  });
  const finalEvent = event({
    base: "main",
    head: "integration/issue-1-large-feature",
    body: "Closes #1",
  });
  const result = await validatePullRequest({ event: finalEvent, config, api });
  assert.equal(result.profile, "feature");

  api.children[0].state = "open";
  await assert.rejects(
    validatePullRequest({ event: finalEvent, config, api }),
    /incomplete children: #2/,
  );
});

test("ordinary pull requests return without GitHub issue inspection", async () => {
  const api = new Proxy({}, {
    get() { throw new Error("ordinary pull request called the GitHub API"); },
  });
  const result = await validatePullRequest({
    event: event({ base: "main", head: "fix/small-bug", body: "" }),
    config,
    api,
  });
  assert.equal(result.profile, "none");
});

test("a merged integration pull request closes its child issue", async () => {
  const api = new FakeApi();
  const result = await closeMergedChild({
    event: event({ merged: true, action: "closed" }),
    config,
    api,
  });
  assert.deepEqual(result, { affected: true, issue: 2 });
  assert.deepEqual(api.closed, [2]);
});

test("validation commands remain structured and profile-specific", () => {
  const calls = [];
  runValidationCommands({
    config,
    profile: "child",
    repositoryRoot: "/tmp/example",
    runner(executable, args, options) {
      calls.push({ executable, args, options });
    },
  });
  assert.deepEqual(calls, [{
    executable: "npm",
    args: ["test", "--", "--unit"],
    options: { cwd: "/tmp/example", stdio: "inherit", shell: false },
  }]);
});

test("the generated frontmatter is readable by trusted workflow code", () => {
  const document = renderRepositoryDocument(config);
  const parsed = parseRepositoryConfig(document.replaceAll("\n", "\r\n"));
  assert.equal(parsed.stableBranch, "main");
  assert.deepEqual(parsed.featureValidationCommands, config.featureValidationCommands);
});
