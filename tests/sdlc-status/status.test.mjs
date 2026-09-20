import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { deriveWorkflowState } from "../../skills/engineering/sdlc-workflow/scripts/lib/state.mjs";
import {
  GitWorktreeSnapshotAdapter,
  LiveGitHubAdapter,
} from "../../skills/engineering/sdlc-status/scripts/lib/live-adapters.mjs";
import {
  repositoryRoots,
  statusView,
} from "../../skills/engineering/sdlc-status/scripts/status.mjs";

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
  childValidationCommands: [],
  featureValidationCommands: [],
  finalMergeApproval: "required",
  featureLabel: "sdlc:feature",
  childLabel: "sdlc:child",
  readyLabel: "ready-for-agent",
};

function fakeGh(executable, args, options) {
  assert.equal(executable, "gh");
  assert.equal(options.shell, false);
  assert.ok(!args.includes("--method"), `status attempted a write: ${args.join(" ")}`);
  if (args[0] === "repo") return JSON.stringify({ nameWithOwner: "example/widgets" });
  if (args[0] === "issue") return JSON.stringify([{ number: 1 }]);
  if (args[0] === "pr") {
    const branch = args[args.indexOf("--head") + 1];
    return JSON.stringify(branch.includes("issue-2-") ? [{
      number: 20,
      state: "OPEN",
      baseRefName: "integration/issue-1-large-feature",
      headRefName: branch,
      headRefOid: "abc123",
      statusCheckRollup: [{ conclusion: "SUCCESS" }],
      reviewDecision: "APPROVED",
    }] : []);
  }
  const endpoint = args.at(-1);
  if (endpoint === "repos/example/widgets/issues/1") {
    return JSON.stringify({
      number: 1,
      state: "open",
      title: "Large feature",
      labels: [{ name: "sdlc:feature" }],
      assignees: [],
    });
  }
  if (endpoint.includes("issues/1/sub_issues")) {
    return JSON.stringify([
      {
        number: 2,
        state: "open",
        title: "Review this child",
        labels: [{ name: "sdlc:child" }],
        assignees: [{ login: "octocat" }],
      },
      {
        number: 3,
        state: "open",
        title: "Ready child",
        labels: [{ name: "sdlc:child" }, { name: "ready-for-agent" }],
        assignees: [],
      },
    ]);
  }
  if (endpoint.includes("dependencies/blocked_by")) return "[]";
  if (endpoint.includes("branches/feat%2Fissue-2-")) return "{}";
  if (endpoint.includes("branches/feat%2Fissue-3-")) {
    const error = new Error("branch not found");
    error.stderr = "HTTP 404";
    throw error;
  }
  throw new Error(`unexpected gh command: ${args.join(" ")}`);
}

test("live status adapters use read-only commands and derive the next command", async () => {
  const github = new LiveGitHubAdapter("/tmp/widgets", config, fakeGh);
  assert.deepEqual(await github.featureNumbers(), [1]);
  const snapshot = await github.snapshot(1);
  const state = deriveWorkflowState({
    repositoryRoot: "/tmp/widgets",
    repositoryConfig: config,
    machineConfig: {
      schemaVersion: 1,
      checkoutRoot: "/tmp",
      worktreeRoot: "/tmp/worktrees",
      worktreeManager: "git",
      executables: { git: "git", github: "gh", supacode: "supacode" },
    },
    githubSnapshot: snapshot,
    worktreeSnapshot: { schemaVersion: 1, worktrees: [] },
    featureNumber: 1,
  });
  const view = statusView(state);
  assert.deepEqual(view.groups.active.map((issue) => issue.number), [2]);
  assert.deepEqual(view.groups.ready.map((issue) => issue.number), [3]);
  assert.equal(view.nextCommand, "/sdlc-finish-issue 2");
});

test("Git worktree inspection parses branches without changing the repository", async () => {
  const calls = [];
  const adapter = new GitWorktreeSnapshotAdapter("/tmp/widgets", (executable, args, options) => {
    calls.push({ executable, args, options });
    return [
      "worktree /tmp/widgets",
      "HEAD abc123",
      "branch refs/heads/main",
      "",
      "worktree /tmp/worktrees/widgets/issue-7-api",
      "HEAD def456",
      "branch refs/heads/feat/issue-7-api",
      "",
    ].join("\n");
  });
  const snapshot = await adapter.snapshot();
  assert.equal(snapshot.worktrees[1].issue, 7);
  assert.equal(snapshot.worktrees[1].branch, "feat/issue-7-api");
  assert.deepEqual(calls[0].args, ["worktree", "list", "--porcelain"]);
  assert.equal(calls[0].options.shell, false);
});

test("status groups blocked, ready, active, and complete children", () => {
  const view = statusView({
    repository: { slug: "example/widgets" },
    feature: { number: 10, status: "in_progress", integrationBranch: "integration/issue-10-x" },
    children: [
      { number: 11, status: "blocked", openBlockers: [12] },
      { number: 12, status: "ready", openBlockers: [] },
      { number: 13, status: "in_progress", openBlockers: [] },
      { number: 14, status: "review", openBlockers: [] },
      { number: 15, status: "complete", openBlockers: [] },
      { number: 16, status: "cancelled", openBlockers: [] },
    ],
    warnings: [],
    nextAction: { kind: "start-issue", issue: 12, summary: "Start issue #12." },
  });
  assert.deepEqual(view.groups.blocked.map((issue) => issue.number), [11]);
  assert.deepEqual(view.groups.ready.map((issue) => issue.number), [12]);
  assert.deepEqual(view.groups.active.map((issue) => issue.number), [13, 14]);
  assert.deepEqual(view.groups.complete.map((issue) => issue.number), [15, 16]);
  assert.equal(view.nextCommand, "/sdlc-start-issue 12");
});

test("all-repository status scans only configured checkout children", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "agent-skills-status-"));
  context.after(() => rm(directory, { recursive: true, force: true }));
  const checkoutRoot = join(directory, "checkouts");
  const configured = join(checkoutRoot, "configured");
  const ordinary = join(checkoutRoot, "ordinary");
  await mkdir(join(configured, "docs", "agents"), { recursive: true });
  await mkdir(ordinary, { recursive: true });
  await writeFile(join(configured, "docs", "agents", "sdlc.md"), "configured\n");
  const machine = join(directory, "machine.json");
  await writeFile(machine, JSON.stringify({
    schemaVersion: 1,
    checkoutRoot,
    worktreeRoot: join(directory, "worktrees"),
    worktreeManager: "git",
  }));

  assert.deepEqual(await repositoryRoots({
    all: true,
    repository: configured,
    "machine-config": machine,
  }), [configured]);
});
