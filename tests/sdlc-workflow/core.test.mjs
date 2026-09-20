import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { stableJson } from "../../skills/engineering/sdlc-workflow/scripts/lib/json.mjs";
import { applyPlan, createPlan, validateAction } from "../../skills/engineering/sdlc-workflow/scripts/lib/plan.mjs";
import { inspectWorkflow } from "../../skills/engineering/sdlc-workflow/scripts/lib/state.mjs";
import { FakeSnapshotAdapter, RecordingActionAdapter } from "../support/fake-sdlc-adapters.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const cli = join(
  repositoryRoot,
  "skills",
  "engineering",
  "sdlc-workflow",
  "scripts",
  "sdlc.mjs",
);

const githubSnapshot = {
  schemaVersion: 1,
  repository: "example/widgets",
  issues: [
    {
      number: 1,
      role: "feature",
      state: "open",
      title: "Coordinated widget delivery",
      labels: ["sdlc:feature"],
      assignees: [],
      blockedBy: [],
    },
    {
      number: 2,
      role: "child",
      parent: 1,
      state: "closed",
      title: "Build the foundation",
      labels: ["sdlc:child"],
      assignees: ["octocat"],
      blockedBy: [],
      branch: "feat/issue-2-foundation",
      pullRequest: {
        number: 20,
        state: "merged",
        base: "integration/issue-1-coordinated-widget-delivery",
        head: "feat/issue-2-foundation",
        headSha: "abc123",
        checks: "passing",
        review: "approved",
      },
    },
    {
      number: 3,
      role: "child",
      parent: 1,
      state: "open",
      title: "Add the runtime",
      labels: ["sdlc:child"],
      assignees: ["octocat"],
      blockedBy: [2],
      branch: "feat/issue-3-runtime",
    },
    {
      number: 4,
      role: "child",
      parent: 1,
      state: "open",
      title: "Ship the commands",
      labels: ["sdlc:child"],
      assignees: [],
      blockedBy: [3],
    },
  ],
};

const worktreeSnapshot = {
  schemaVersion: 1,
  worktrees: [
    {
      id: "worktree-3",
      issue: 3,
      branch: "feat/issue-3-runtime",
      status: "active",
    },
  ],
};

async function fixture() {
  const directory = await mkdtemp(join(tmpdir(), "agent-skills-sdlc-"));
  const repository = join(directory, "widgets");
  const worktreeRoot = join(directory, "worktrees");
  await mkdir(join(repository, "docs", "agents"), { recursive: true });
  await mkdir(worktreeRoot, { recursive: true });
  execFileSync("git", ["init", "--initial-branch=main", repository], { stdio: "ignore" });
  await writeFile(
    join(repository, "docs", "agents", "sdlc.md"),
    `---
schemaVersion: 1
provider: github
stableBranch: main
integrationBranchPattern: integration/issue-{issue}-{slug}
childBranchPattern: feat/issue-{issue}-{slug}
worktreeRetention: feature
closeChildOnIntegrationMerge: true
autoMergeChildPullRequests: true
finalMergeApproval: required
featureLabel: sdlc:feature
childLabel: sdlc:child
readyLabel: ready-for-agent
---

# SDLC configuration
`.replaceAll("\n", "\r\n"),
  );
  const machine = join(directory, "machine.json");
  await writeFile(machine, stableJson({
    schemaVersion: 1,
    checkoutRoot: directory,
    worktreeRoot,
    worktreeManager: "git",
    executables: { git: "git", github: "gh", supacode: "supacode" },
  }));
  return { directory, repository, machine };
}

async function inspect(currentFixture, github = githubSnapshot, worktrees = worktreeSnapshot) {
  return inspectWorkflow({
    repositoryRoot: currentFixture.repository,
    machineConfigPath: currentFixture.machine,
    githubAdapter: new FakeSnapshotAdapter(github),
    worktreeAdapter: new FakeSnapshotAdapter(worktrees),
    featureNumber: 1,
  });
}

test("inspection derives stable status and the next issue from fake adapters", async (context) => {
  const currentFixture = await fixture();
  context.after(() => rm(currentFixture.directory, { recursive: true, force: true }));

  const first = await inspect(currentFixture);
  const second = await inspect(currentFixture);
  const reorderedGithub = {
    ...githubSnapshot,
    issues: [...githubSnapshot.issues].reverse(),
  };
  const reorderedWorktrees = {
    ...worktreeSnapshot,
    worktrees: [...worktreeSnapshot.worktrees].reverse(),
  };
  const reordered = await inspect(currentFixture, reorderedGithub, reorderedWorktrees);

  assert.equal(stableJson(first), stableJson(second));
  assert.equal(stableJson(first), stableJson(reordered));
  assert.equal(first.feature.status, "in_progress");
  assert.equal(first.feature.integrationBranch, "integration/issue-1-coordinated-widget-delivery");
  assert.deepEqual(
    first.children.map((child) => [child.number, child.status]),
    [[2, "complete"], [3, "in_progress"], [4, "blocked"]],
  );
  assert.deepEqual(first.nextAction, {
    kind: "continue-issue",
    issue: 3,
    summary: "Continue issue #3.",
  });
  assert.match(first.freshness.fingerprint, /^[a-f0-9]{64}$/);
});

test("plan and apply use typed adapters and live freshness evidence", async (context) => {
  const currentFixture = await fixture();
  context.after(() => rm(currentFixture.directory, { recursive: true, force: true }));
  const state = await inspect(currentFixture);
  const plan = createPlan(state, {
    schemaVersion: 1,
    operation: "mark-ready",
    actions: [
      {
        id: "ready-4",
        adapter: "github",
        operation: "add-label",
        parameters: { issue: 4, label: "ready-for-agent" },
      },
    ],
  });
  const github = new RecordingActionAdapter();
  const report = await applyPlan({
    plan,
    loadCurrentState: () => inspect(currentFixture),
    adapters: { github },
  });

  assert.equal(report.status, "applied");
  assert.equal(report.planId, plan.planId);
  assert.deepEqual(github.calls, [{
    operation: "add-label",
    parameters: { issue: 4, label: "ready-for-agent" },
  }]);
});

test("apply rejects stale evidence before an adapter runs", async (context) => {
  const currentFixture = await fixture();
  context.after(() => rm(currentFixture.directory, { recursive: true, force: true }));
  const state = await inspect(currentFixture);
  const plan = createPlan(state, {
    schemaVersion: 1,
    operation: "mark-ready",
    actions: [{
      id: "ready-4",
      adapter: "github",
      operation: "add-label",
      parameters: { issue: 4, label: "ready-for-agent" },
    }],
  });
  const changed = structuredClone(githubSnapshot);
  changed.issues.find((issue) => issue.number === 3).state = "closed";
  const github = new RecordingActionAdapter();

  await assert.rejects(
    applyPlan({
      plan,
      loadCurrentState: () => inspect(currentFixture, changed),
      adapters: { github },
    }),
    /plan is stale/,
  );
  assert.deepEqual(github.calls, []);
});

test("action validation rejects shell-shaped input", () => {
  assert.throws(
    () => validateAction({
      id: "unsafe",
      adapter: "git",
      operation: "create-branch",
      parameters: { shell: "git branch unsafe && rm -rf ." },
    }),
    /cannot contain 'shell'/,
  );
  assert.throws(
    () => validateAction({
      id: "unknown",
      adapter: "shell",
      operation: "run",
      parameters: {},
    }),
    /unknown adapter/,
  );
});

test("the CLI emits canonical inspection and plan JSON", async (context) => {
  const currentFixture = await fixture();
  context.after(() => rm(currentFixture.directory, { recursive: true, force: true }));
  const githubFile = join(currentFixture.directory, "github.json");
  const worktreeFile = join(currentFixture.directory, "worktrees.json");
  const stateFile = join(currentFixture.directory, "state.json");
  const requestFile = join(currentFixture.directory, "request.json");
  const planFile = join(currentFixture.directory, "plan.json");
  await writeFile(githubFile, stableJson(githubSnapshot));
  await writeFile(worktreeFile, stableJson(worktreeSnapshot));

  execFileSync(process.execPath, [
    cli,
    "inspect",
    "--repository", currentFixture.repository,
    "--machine-config", currentFixture.machine,
    "--github-snapshot", githubFile,
    "--worktree-snapshot", worktreeFile,
    "--feature", "1",
    "--output", stateFile,
  ]);
  const state = JSON.parse(await readFile(stateFile, "utf8"));
  await writeFile(requestFile, stableJson({
    schemaVersion: 1,
    operation: "mark-ready",
    actions: [{
      id: "ready-4",
      adapter: "github",
      operation: "add-label",
      parameters: { issue: 4, label: "ready-for-agent" },
    }],
  }));
  execFileSync(process.execPath, [
    cli,
    "plan",
    "--state", stateFile,
    "--request", requestFile,
    "--output", planFile,
  ]);
  const planText = await readFile(planFile, "utf8");
  const plan = JSON.parse(planText);
  assert.equal(planText, stableJson(plan));

  const verify = spawnSync(process.execPath, [
    cli,
    "verify-plan",
    "--plan", planFile,
    "--state", stateFile,
  ], { encoding: "utf8" });
  assert.equal(verify.status, 0, verify.stderr);
  assert.equal(JSON.parse(verify.stdout).fresh, true);
});

test("all workflow schemas are valid JSON with version 1 contracts", async () => {
  const schemaDirectory = join(
    repositoryRoot,
    "skills",
    "engineering",
    "sdlc-workflow",
    "schemas",
  );
  for (const name of [
    "action-plan.schema.json",
    "issue-metadata.schema.json",
    "machine-config.schema.json",
    "repository-config.schema.json",
    "workflow-state.schema.json",
  ]) {
    const schema = JSON.parse(await readFile(join(schemaDirectory, name), "utf8"));
    assert.equal(schema.$schema, "https://json-schema.org/draft/2020-12/schema");
    assert.ok(schema.$id.endsWith(name));
  }
});
