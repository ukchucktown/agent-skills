import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  mkdirSync,
  mkdtempSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  issueReferences,
  parseIssueBody,
} from "../skills/engineering/gh-issue/scripts/lib/issue-body.mjs";
import {
  branchMatchesIssue,
  buildStatus,
} from "../skills/engineering/gh-issue/scripts/lib/status-model.mjs";
import {
  inferIssueNumber,
  loadFixture,
} from "../skills/engineering/gh-issue/scripts/lib/runtime.mjs";
import {
  parseArguments,
  runCommand,
} from "../skills/engineering/gh-issue/scripts/gh-issue.mjs";

function issue(number, overrides = {}) {
  return {
    number,
    title: `Issue ${number}`,
    state: "OPEN",
    url: `https://github.com/example/project/issues/${number}`,
    body: "",
    assignees: [],
    labels: [],
    parent: null,
    subIssues: { nodes: [] },
    blockedBy: { nodes: [] },
    ...overrides,
  };
}

function fakeClient(issues) {
  const byNumber = new Map(issues.map((entry) => [entry.number, entry]));
  return {
    repository: "example/project",
    defaultBranch: "main",
    async getIssue(number) {
      const result = byNumber.get(Number(number));
      if (!result) throw new Error(`Missing issue ${number}`);
      return result;
    },
    async searchIssuesReferencing(number) {
      return issues.filter((entry) =>
        issueReferences(entry.body ?? "").includes(Number(number)),
      );
    },
  };
}

test("body parser recognizes explicit and list relationships without treating prose references as children", () => {
  const parsed = parseIssueBody(`
Parent: #10

Issue #99 provides useful background.

- [ ] #11
- [ ] Issue #98 belongs to another effort.

## Children

- #12
- https://github.com/example/project/issues/13

## Blocked by

- #14
- #15
`);

  assert.deepEqual(parsed, {
    parentNumbers: [10],
    childNumbers: [11, 12, 13],
    blockedByNumbers: [14, 15],
  });
});

test("body parser recognizes heading-based parent and inline blockers", () => {
  const parsed = parseIssueBody(`
## Parent

#20

Blocked by: #21, #22
`);
  assert.deepEqual(parsed.parentNumbers, [20]);
  assert.deepEqual(parsed.blockedByNumbers, [21, 22]);
});

test("branch matching and inference require issue-shaped names", () => {
  assert.equal(branchMatchesIssue("feat/issue-151-connectors", 151), true);
  assert.equal(branchMatchesIssue("issue/151-connectors", 151), true);
  assert.equal(branchMatchesIssue("integration/148-agent-config", 148), true);
  assert.equal(branchMatchesIssue("release/2026-151", 151), false);
  assert.equal(branchMatchesIssue("release/151-hotfix", 151), false);
  assert.equal(
    inferIssueNumber({
      currentBranch: "feat/issue-151-connectors",
      worktrees: [{ branch: "feat/issue-152-other-work" }],
    }),
    151,
  );
});

test("status resolves nested compound work and recommends an already-started standalone issue", async () => {
  const issues = [
    issue(100, {
      title: "Program",
      body: "## Tasks\n- [x] #101\n- [ ] #102",
    }),
    issue(101, {
      title: "Completed task",
      state: "CLOSED",
      body: "Parent: #100",
    }),
    issue(102, {
      title: "Nested feature",
      body: "## Parent\n#100\n\n## Children\n- #103\n- #104",
    }),
    issue(103, { title: "Started task", body: "Parent: #102" }),
    issue(104, {
      title: "Blocked task",
      body: "Parent: #102\nBlocked by: #105",
    }),
    issue(105, { title: "External blocker" }),
  ];

  const result = await buildStatus({
    client: fakeClient(issues),
    issueNumber: 100,
    workState: {
      branches: [{ name: "issue/103-started-task", remote: false }],
      worktrees: [],
      pullRequests: [],
    },
  });

  assert.equal(result.classification, "compound");
  assert.equal(result.workflowState, "in_progress");
  assert.deepEqual(
    result.children.completed.map((entry) => entry.number),
    [101],
  );
  assert.deepEqual(
    result.children.in_progress.map((entry) => entry.number),
    [102],
  );
  assert.equal(result.recommendation.issue.number, 103);
  assert.match(result.recommendation.reason, /work in progress/i);
  assert.match(result.nextAction, /recommended #103/i);
});

test("status reports conflicting parent evidence instead of choosing", async () => {
  const issues = [
    issue(10, { title: "Native parent" }),
    issue(20, { title: "Body parent" }),
    issue(30, {
      title: "Conflicted child",
      parent: { number: 10, title: "Native parent", state: "OPEN" },
      body: "Parent: #20",
    }),
  ];

  const result = await buildStatus({
    client: fakeClient(issues),
    issueNumber: 30,
    workState: { branches: [], worktrees: [], pullRequests: [] },
  });

  assert.equal(result.conflicts[0].kind, "multiple_parents");
  assert.deepEqual(
    result.conflicts[0].candidates.map((entry) => entry.number),
    [10, 20],
  );
  assert.match(result.nextAction, /resolve/i);
});

test("status associates a pull request only through a branch or an explicit issue phrase", async () => {
  const client = fakeClient([issue(50, { title: "Focused work" })]);
  const unrelated = await buildStatus({
    client,
    issueNumber: 50,
    workState: {
      branches: [],
      worktrees: [],
      pullRequests: [
        {
          number: 7,
          title: "Unrelated change",
          state: "OPEN",
          headRefName: "chore/docs",
          body: "See #50 for background.",
        },
      ],
    },
  });
  assert.equal(unrelated.workflowState, "ready");
  assert.equal(unrelated.pullRequests.length, 0);

  const merged = await buildStatus({
    client,
    issueNumber: 50,
    workState: {
      branches: [],
      worktrees: [],
      pullRequests: [
        {
          number: 8,
          title: "Focused change",
          state: "MERGED",
          mergedAt: "2026-09-20T12:00:00Z",
          headRefName: "chore/docs",
          body: "Closes #50",
        },
      ],
    },
  });
  assert.equal(merged.workflowState, "in_progress");
  assert.match(merged.nextAction, /remains open/i);
});

test("fixture mode returns a bounded authored-or-assigned selection", async () => {
  const directory = mkdtempSync(join(tmpdir(), "gh-issue-test-"));
  const fixturePath = join(directory, "fixture.json");
  writeFileSync(
    fixturePath,
    JSON.stringify({
      repository: { nameWithOwner: "example/project", defaultBranch: "main" },
      viewer: { login: "octocat" },
      issues: [
        issue(1, { author: { login: "octocat" }, updatedAt: "2026-09-20T12:00:00Z" }),
        issue(2, {
          assignees: [{ login: "octocat" }],
          updatedAt: "2026-09-20T13:00:00Z",
        }),
        issue(3, { author: { login: "someone-else" } }),
      ],
    }),
  );

  try {
    const { client } = loadFixture(fixturePath);
    const candidates = await client.listCandidates();
    assert.deepEqual(
      candidates.map((entry) => entry.number),
      [2, 1],
    );

    const result = await runCommand(
      parseArguments(["status", "--fixture", fixturePath, "--json"]),
    );
    assert.equal(result.kind, "selection_required");
    assert.deepEqual(
      result.candidates.map((entry) => entry.number),
      [2, 1],
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("mutating commands remain unavailable in the read-only foundation", async () => {
  const result = await runCommand(parseArguments(["start", "151"]));
  assert.equal(result.kind, "unavailable");
  assert.match(result.message, /read-only foundation/i);
});

test("helper runs when the installed skill is a symbolic link", () => {
  const directory = mkdtempSync(join(tmpdir(), "gh-issue-entrypoint-"));
  const testDirectory = dirname(fileURLToPath(import.meta.url));
  const source = resolve(testDirectory, "../skills/engineering/gh-issue");
  const installedSkill = join(directory, "skills", "gh-issue");

  try {
    mkdirSync(dirname(installedSkill), { recursive: true });
    symlinkSync(
      source,
      installedSkill,
      process.platform === "win32" ? "junction" : "dir",
    );
    const installedHelper = join(installedSkill, "scripts", "gh-issue.mjs");
    const result = spawnSync(process.execPath, [installedHelper, "--help"], {
      encoding: "utf8",
    });

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /^Usage:/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
