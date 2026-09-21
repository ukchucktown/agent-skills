import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

import {
  buildStartPlan,
  parseArguments,
  parseGitHubRemote,
  parseWorktrees,
  slugify,
  startIssue,
} from "../skills/engineering/gh-issue/scripts/start.mjs";

test("parses the supported command line", () => {
  assert.deepEqual(
    parseArguments([
      "--issue",
      "42",
      "--repository",
      "/repo",
      "--manager",
      "git",
      "--dry-run",
    ]),
    {
      issue: 42,
      repository: "/repo",
      manager: "git",
      dryRun: true,
      json: false,
      fetch: true,
    },
  );
  assert.throws(() => parseArguments(["--issue", "0"]), /positive integer/);
  assert.throws(() => parseArguments(["--issue", "1", "--manager", "other"]), /auto/);
});

test("parses common GitHub remotes", () => {
  assert.deepEqual(parseGitHubRemote("git@github.com:owner/repo.git"), {
    owner: "owner",
    name: "repo",
  });
  assert.deepEqual(parseGitHubRemote("https://github.com/owner/repo.git"), {
    owner: "owner",
    name: "repo",
  });
  assert.throws(() => parseGitHubRemote("https://example.com/owner/repo"), /not a GitHub/);
});

test("creates stable slugs", () => {
  assert.equal(slugify("Add fast gh-issue start command"), "add-fast-gh-issue-start-command");
  assert.equal(slugify("Crème & API"), "creme-api");
});

test("plans a standalone issue from the stable branch", () => {
  const result = buildStartPlan({
    issue: {
      number: 25,
      title: "Add fast start",
      state: "OPEN",
      subIssues: { totalCount: 0 },
      parent: null,
    },
    defaultBranch: "main",
    repositoryName: "agent-skills",
    worktreeRoot: "/worktrees",
  });
  assert.equal(result.classification, "standalone");
  assert.deepEqual(result.steps, [
    {
      issue: 25,
      title: "Add fast start",
      kind: "task",
      branch: "feat/issue-25-add-fast-start",
      baseBranch: "main",
      worktreeName: "issue-25-add-fast-start",
      destination: path.join("/worktrees", "agent-skills", "issue-25-add-fast-start"),
    },
  ]);
});

test("plans only the ancestor integration path and requested child", () => {
  const result = buildStartPlan({
    issue: {
      number: 12,
      title: "Leaf",
      state: "OPEN",
      subIssues: { totalCount: 0 },
      parent: {
        number: 11,
        title: "Nested feature",
        state: "OPEN",
        parent: {
          number: 10,
          title: "Top feature",
          state: "OPEN",
          parent: null,
        },
      },
    },
    defaultBranch: "main",
    repositoryName: "example",
    worktreeRoot: "/worktrees",
  });
  assert.deepEqual(
    result.steps.map(({ issue, kind, branch, baseBranch }) => ({
      issue,
      kind,
      branch,
      baseBranch,
    })),
    [
      {
        issue: 10,
        kind: "integration",
        branch: "integration/issue-10-top-feature",
        baseBranch: "main",
      },
      {
        issue: 11,
        kind: "integration",
        branch: "integration/issue-11-nested-feature",
        baseBranch: "integration/issue-10-top-feature",
      },
      {
        issue: 12,
        kind: "task",
        branch: "feat/issue-12-leaf",
        baseBranch: "integration/issue-11-nested-feature",
      },
    ],
  );
});

test("plans a compound issue as an integration worktree", () => {
  const result = buildStartPlan({
    issue: {
      number: 10,
      title: "Feature",
      state: "OPEN",
      subIssues: { totalCount: 3 },
      parent: null,
    },
    defaultBranch: "trunk",
    repositoryName: "example",
    worktreeRoot: "/worktrees",
  });
  assert.equal(result.classification, "compound");
  assert.equal(result.steps[0].kind, "integration");
  assert.equal(result.steps[0].baseBranch, "trunk");
});

test("parses branches from git worktree porcelain output", () => {
  assert.deepEqual(
    parseWorktrees(
      "worktree /repo\nHEAD abc\nbranch refs/heads/main\n\n" +
        "worktree /worktrees/issue-1\nHEAD def\nbranch refs/heads/feat/issue-1-test\n",
    ),
    [
      { path: "/repo", branch: "main" },
      { path: "/worktrees/issue-1", branch: "feat/issue-1-test" },
    ],
  );
});

test("uses one GitHub call and bounded Supacode mutations", () => {
  const fixtureRoot = mkdtempSync(path.join(tmpdir(), "gh-issue-start-"));
  try {
    const primary = path.join(fixtureRoot, "repos", "example");
    const linked = path.join(fixtureRoot, "linked", "example-child");
    const worktreeRoot = path.join(fixtureRoot, "worktrees");
    mkdirSync(path.join(primary, ".git"), { recursive: true });
    mkdirSync(linked, { recursive: true });
    const calls = [];
    const branchesByDestination = new Map();
    const githubResponse = {
      data: {
        repository: {
          nameWithOwner: "owner/example",
          defaultBranchRef: { name: "main" },
          issue: {
            number: 12,
            title: "Leaf",
            state: "OPEN",
            url: "https://github.com/owner/example/issues/12",
            subIssues: { totalCount: 0 },
            parent: {
              number: 10,
              title: "Feature",
              state: "OPEN",
              url: "https://github.com/owner/example/issues/10",
              parent: null,
            },
          },
        },
      },
    };

    const run = (command, args, options = {}) => {
      calls.push({ command, args, cwd: options.cwd });
      const result = (stdout = "", ok = true) => ({ ok, stdout, stderr: "" });
      if (command === "gh") return result(JSON.stringify(githubResponse));
      if (command === "supacode" && args[0] === "repo" && args[1] === "list") {
        return result(encodeURIComponent(`${primary}/`));
      }
      if (command === "supacode") {
        const branch = args[args.indexOf("--branch") + 1];
        const name = args[args.indexOf("--name") + 1];
        branchesByDestination.set(path.join(worktreeRoot, "example", name), branch);
        return result(encodeURIComponent(path.join(worktreeRoot, "example", name)));
      }
      assert.equal(command, "git");
      if (args[0] === "check-ref-format") return result();
      const repository = args[1];
      const gitArgs = args.slice(2);
      if (gitArgs[0] === "rev-parse" && gitArgs.includes("--show-toplevel")) {
        return result(linked);
      }
      if (gitArgs[0] === "rev-parse" && gitArgs.includes("--git-common-dir")) {
        return result(path.join(primary, ".git"));
      }
      if (gitArgs[0] === "remote") return result("git@github.com:owner/example.git");
      if (gitArgs[0] === "fetch") return result();
      if (gitArgs[0] === "worktree" && gitArgs[1] === "list") return result();
      if (gitArgs[0] === "for-each-ref" && gitArgs.includes("refs/remotes/origin")) {
        return result(
          gitArgs.includes("--format=%(refname:short)")
            ? "main\norigin/main"
            : "refs/heads/main\nrefs/remotes/origin/main",
        );
      }
      if (gitArgs[0] === "for-each-ref") return result("main");
      if (gitArgs[0] === "branch" && gitArgs[1] === "--show-current") {
        return result(branchesByDestination.get(repository));
      }
      if (gitArgs[0] === "show-ref") return result("", false);
      if (gitArgs[0] === "push") return result();
      throw new Error(`Unexpected command: ${command} ${args.join(" ")}`);
    };

    const result = startIssue(
      {
        issue: 12,
        repository: linked,
        manager: "supacode",
        worktreeRoot,
        config: path.join(fixtureRoot, "missing-config.json"),
        fetch: true,
        dryRun: false,
      },
      { run },
    );

    assert.equal(result.classification, "standalone");
    assert.equal(result.manager, "supacode");
    assert.equal(calls.filter((call) => call.command === "gh").length, 1);
    assert.equal(
      calls.filter(
        (call) => call.command === "supacode" && call.args[1] === "worktree-new",
      ).length,
      2,
    );
    const push = calls.find(
      (call) => call.command === "git" && call.args.includes("push"),
    );
    assert.ok(push.args.includes("integration/issue-10-feature"));
    assert.ok(!push.args.includes("feat/issue-12-leaf"));
  } finally {
    rmSync(fixtureRoot, { recursive: true, force: true });
  }
});

test("creates and publishes an integration path from a linked worktree", () => {
  const fixtureRoot = mkdtempSync(path.join(tmpdir(), "gh-issue-start-git-"));
  try {
    const origin = path.join(fixtureRoot, "origin.git");
    const primary = path.join(fixtureRoot, "repos", "example");
    const linked = path.join(fixtureRoot, "linked", "context");
    const worktreeRoot = path.join(fixtureRoot, "worktrees");
    mkdirSync(path.dirname(primary), { recursive: true });
    mkdirSync(path.dirname(linked), { recursive: true });

    const execute = (command, args, options = {}) => {
      const result = spawnSync(command, args, {
        cwd: options.cwd,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      });
      if (result.status !== 0 && !options.allowFailure) {
        throw new Error(result.stderr || `${command} failed`);
      }
      return {
        ok: result.status === 0,
        stdout: result.stdout.trim(),
        stderr: result.stderr.trim(),
      };
    };
    const git = (repository, ...args) =>
      execute("git", ["-C", repository, ...args]).stdout;

    execute("git", ["init", "--bare", origin]);
    execute("git", ["init", "-b", "main", primary]);
    git(primary, "config", "user.name", "Fixture");
    git(primary, "config", "user.email", "fixture@example.com");
    git(primary, "commit", "--allow-empty", "-m", "Initial commit");
    git(primary, "remote", "add", "origin", origin);
    git(primary, "push", "-u", "origin", "main");
    git(primary, "worktree", "add", "-b", "context", linked, "main");
    const githubResponse = {
      data: {
        repository: {
          nameWithOwner: "owner/example",
          defaultBranchRef: { name: "main" },
          issue: {
            number: 31,
            title: "Native child",
            state: "OPEN",
            url: "https://github.com/owner/example/issues/31",
            subIssues: { totalCount: 0 },
            parent: {
              number: 30,
              title: "Native feature",
              state: "OPEN",
              url: "https://github.com/owner/example/issues/30",
              parent: null,
            },
          },
        },
      },
    };
    const run = (command, args, options = {}) => {
      if (command === "gh") {
        return { ok: true, stdout: JSON.stringify(githubResponse), stderr: "" };
      }
      if (command === "git" && args.slice(2).join(" ") === "remote get-url origin") {
        return { ok: true, stdout: "git@github.com:owner/example.git", stderr: "" };
      }
      return execute(command, args, options);
    };

    const result = startIssue(
      {
        issue: 31,
        repository: linked,
        manager: "git",
        worktreeRoot,
        config: path.join(fixtureRoot, "missing-config.json"),
        fetch: false,
        dryRun: false,
      },
      { run },
    );

    const destination = path.join(worktreeRoot, "example", "issue-31-native-child");
    assert.equal(result.manager, "git");
    assert.equal(git(destination, "branch", "--show-current"), "feat/issue-31-native-child");
    assert.equal(result.actions[1].destination, destination);
    assert.match(
      git(origin, "show-ref", "refs/heads/integration/issue-30-native-feature"),
      /integration\/issue-30-native-feature/,
    );
    assert.throws(
      () => git(origin, "show-ref", "refs/heads/feat/issue-31-native-child"),
      /fatal|failed/,
    );
  } finally {
    rmSync(fixtureRoot, { recursive: true, force: true });
  }
});
