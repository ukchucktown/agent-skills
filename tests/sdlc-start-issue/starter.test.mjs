import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  GitWorktreeAdapter,
  SupacodeWorktreeAdapter,
} from "../../skills/engineering/sdlc-start-issue/scripts/lib/adapters.mjs";
import {
  applyStartPlan,
  createStartPlan,
} from "../../skills/engineering/sdlc-start-issue/scripts/lib/starter.mjs";

const repositoryConfig = {
  featureLabel: "sdlc:feature",
  childLabel: "sdlc:child",
  readyLabel: "ready-for-agent",
  integrationBranchPattern: "integration/issue-{issue}-{slug}",
  childBranchPattern: "feat/issue-{issue}-{slug}",
};

const machineConfig = {
  schemaVersion: 1,
  checkoutRoot: "/projects",
  worktreeRoot: "/projects/worktrees",
  worktreeManager: "supacode",
};

function snapshot(overrides = {}) {
  return {
    schemaVersion: 1,
    repository: "example/widgets",
    actor: "current-user",
    machine: {
      worktreeRoot: machineConfig.worktreeRoot,
      worktreeManager: machineConfig.worktreeManager,
    },
    issue: {
      number: 6,
      state: "open",
      title: "Start worktrees",
      labels: ["sdlc:child", "ready-for-agent"],
      assignees: [],
    },
    parent: {
      number: 1,
      state: "open",
      title: "Large feature",
      labels: ["sdlc:feature"],
    },
    blockers: [{ number: 4, state: "closed", title: "Setup" }],
    comments: [],
    pullRequests: [],
    branch: "feat/issue-6-start-worktrees",
    integrationBranch: "integration/issue-1-large-feature",
    integrationBranchExists: true,
    branchExists: false,
    worktrees: [],
    ...overrides,
  };
}

test("start planning claims a ready issue without recording a local path", () => {
  const plan = createStartPlan({
    snapshot: snapshot(),
    repositoryConfig,
    machineConfig,
    repositoryRoot: "/projects/widgets",
  });
  assert.deepEqual(plan.actions.map((action) => action.id), [
    "create-worktree",
    "assign-issue",
    "remove-ready-label",
    "record-branch",
  ]);
  const comment = plan.actions.find((action) => action.id === "record-branch").parameters.body;
  assert.match(comment, /feat\/issue-6-start-worktrees/);
  assert.doesNotMatch(comment, /\/projects\/worktrees/);
  assert.equal(plan.worktree.manager, "supacode");
});

test("start planning resolves the primary checkout from a task worktree", () => {
  const plan = createStartPlan({
    snapshot: snapshot(),
    repositoryConfig,
    machineConfig,
    repositoryRoot: "/projects/worktrees/widgets/integration-issue-1",
  });
  const create = plan.actions.find((action) => action.id === "create-worktree");
  assert.equal(create.parameters.repositoryRoot, "/projects/widgets");
  assert.equal(create.parameters.location, "/projects/worktrees/widgets");
  assert.equal(
    create.parameters.root,
    "/projects/worktrees/widgets/issue-6-start-worktrees",
  );
  assert.equal(plan.repositoryRoot, "/projects/worktrees/widgets/integration-issue-1");
});

test("start refuses open blockers, pull requests, and unreviewed assignment conflicts", () => {
  assert.throws(() => createStartPlan({
    snapshot: snapshot({ blockers: [{ number: 4, state: "open" }] }),
    repositoryConfig,
    machineConfig,
    repositoryRoot: "/projects/widgets",
  }), /open blockers: #4/);

  assert.throws(() => createStartPlan({
    snapshot: snapshot({ pullRequests: [{ number: 44, state: "closed" }] }),
    repositoryConfig,
    machineConfig,
    repositoryRoot: "/projects/widgets",
  }), /already has pull request\(s\): #44/);

  const conflicted = snapshot();
  conflicted.issue.assignees = ["teammate"];
  assert.throws(() => createStartPlan({
    snapshot: conflicted,
    repositoryConfig,
    machineConfig,
    repositoryRoot: "/projects/widgets",
  }), /explicit override reason is required/);
});

test("an assignment override records the people and reason", () => {
  const conflicted = snapshot();
  conflicted.issue.assignees = ["teammate"];
  const plan = createStartPlan({
    snapshot: conflicted,
    repositoryConfig,
    machineConfig,
    repositoryRoot: "/projects/widgets",
    overrideAssignment: "The teammate asked me to continue.",
  });
  const body = plan.actions.find((action) => action.id === "record-branch").parameters.body;
  assert.ok(plan.actions.some((action) => action.id === "unassign-teammate"));
  assert.match(body, /@current-user took over from @teammate/);
  assert.match(body, /The teammate asked me to continue\./);
});

test("a prepared worktree is reused", () => {
  const branch = "feat/issue-6-start-worktrees";
  const current = snapshot({
    branchExists: true,
    worktrees: [{
      id: "worktree-id",
      root: "/projects/worktrees/widgets/issue-6-start-worktrees",
      branch,
      manager: "supacode",
    }],
  });
  current.issue.assignees = ["current-user"];
  current.issue.labels = ["sdlc:child"];
  current.comments = [{ id: 1, body: `<!-- agent-skills:sdlc-branch:${branch} -->` }];
  const plan = createStartPlan({
    snapshot: current,
    repositoryConfig,
    machineConfig,
    repositoryRoot: "/projects/widgets",
  });
  assert.deepEqual(plan.actions, []);
  assert.equal(plan.worktree.id, "worktree-id");
});

test("apply rejects stale evidence before an adapter runs", async () => {
  const current = snapshot();
  const plan = createStartPlan({
    snapshot: current,
    repositoryConfig,
    machineConfig,
    repositoryRoot: "/projects/widgets",
  });
  const calls = [];
  await assert.rejects(applyStartPlan({
    plan,
    inspect: async () => ({ ...current, branchExists: true }),
    adapters: {
      worktree: { execute: async (...args) => calls.push(args) },
      github: { execute: async (...args) => calls.push(args) },
    },
  }), /start plan is stale/);
  assert.deepEqual(calls, []);
});

test("Supacode captures its returned worktree ID", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "agent-skills-supacode-"));
  context.after(() => rm(directory, { recursive: true, force: true }));
  const calls = [];
  const adapter = new SupacodeWorktreeAdapter(directory, (executable, args, options) => {
    calls.push({ executable, args, options });
    return "%2Ftmp%2Fworktree%2F\n";
  });
  const result = await adapter.execute("create", {
    repositoryRoot: directory,
    branch: "feat/issue-6-start-worktrees",
    base: "origin/integration/issue-1-large-feature",
    fetchBranch: "integration/issue-1-large-feature",
    location: join(directory, "worktrees", "widgets"),
    name: "issue-6-start-worktrees",
    root: join(directory, "worktrees", "widgets", "issue-6-start-worktrees"),
  });
  assert.equal(result.id, "%2Ftmp%2Fworktree%2F");
  assert.equal(result.manager, "supacode");
  assert.equal(calls[0].executable, "supacode");
  assert.ok(calls[0].args.includes("--background"));
  assert.ok(calls[0].args.includes("--fetch"));
  assert.equal(calls[0].options.shell, false);
});

test("native Git creates the same logical branch under the configured root", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "agent-skills-git-worktree-"));
  context.after(() => rm(directory, { recursive: true, force: true }));
  const repository = join(directory, "widgets");
  const worktreeRoot = join(directory, "worktrees", "widgets", "issue-6-start-worktrees");
  execFileSync("git", ["init", "--initial-branch=main", repository], { stdio: "ignore" });
  execFileSync("git", ["config", "user.name", "Test User"], { cwd: repository });
  execFileSync("git", ["config", "user.email", "test@example.com"], { cwd: repository });
  await writeFile(join(repository, "README.md"), "fixture\n");
  execFileSync("git", ["add", "README.md"], { cwd: repository });
  execFileSync("git", ["commit", "-m", "fixture"], { cwd: repository, stdio: "ignore" });
  execFileSync("git", ["branch", "integration/issue-1-large-feature"], { cwd: repository });

  const adapter = new GitWorktreeAdapter(repository);
  const result = await adapter.execute("create", {
    repositoryRoot: repository,
    branch: "feat/issue-6-start-worktrees",
    base: "integration/issue-1-large-feature",
    fetchBranch: null,
    location: join(directory, "worktrees", "widgets"),
    name: "issue-6-start-worktrees",
    root: worktreeRoot,
  });
  assert.equal(result.manager, "git");
  assert.equal(
    execFileSync("git", ["branch", "--show-current"], { cwd: worktreeRoot, encoding: "utf8" }).trim(),
    "feat/issue-6-start-worktrees",
  );
  assert.equal(
    (await readFile(join(worktreeRoot, "README.md"), "utf8")).replaceAll("\r\n", "\n"),
    "fixture\n",
  );
});

test("native Git runs fetch and worktree creation from the recovered primary checkout", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "agent-skills-git-cwd-"));
  context.after(() => rm(directory, { recursive: true, force: true }));
  const primary = join(directory, "widgets");
  const task = join(directory, "worktrees", "widgets", "integration-issue-1");
  const calls = [];
  const adapter = new GitWorktreeAdapter(task, (executable, args, options) => {
    calls.push({ executable, args, options });
    return "";
  });

  await adapter.execute("create", {
    repositoryRoot: primary,
    branch: "feat/issue-6-start-worktrees",
    base: "origin/integration/issue-1-large-feature",
    fetchBranch: "integration/issue-1-large-feature",
    location: join(directory, "worktrees", "widgets"),
    name: "issue-6-start-worktrees",
    root: join(directory, "worktrees", "widgets", "issue-6-start-worktrees"),
  });

  assert.deepEqual(calls.map((call) => ({ args: call.args, cwd: call.options.cwd })), [
    {
      args: ["fetch", "origin", "integration/issue-1-large-feature"],
      cwd: primary,
    },
    {
      args: [
        "worktree",
        "add",
        "-b",
        "feat/issue-6-start-worktrees",
        join(directory, "worktrees", "widgets", "issue-6-start-worktrees"),
        "origin/integration/issue-1-large-feature",
      ],
      cwd: primary,
    },
  ]);
});
