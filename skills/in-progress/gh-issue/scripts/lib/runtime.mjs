import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { issueReferences } from "./issue-body.mjs";

const ISSUE_FIELDS = [
  "number",
  "title",
  "state",
  "url",
  "body",
  "updatedAt",
  "author",
  "assignees",
  "labels",
  "parent",
  "subIssues",
  "blockedBy",
].join(",");

const PR_FIELDS = [
  "number",
  "title",
  "state",
  "isDraft",
  "headRefName",
  "baseRefName",
  "url",
  "body",
  "mergedAt",
  "statusCheckRollup",
  "closingIssuesReferences",
  "updatedAt",
].join(",");

function run(command, args, cwd, { allowFailure = false } = {}) {
  try {
    return execFileSync(command, args, {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 20 * 1024 * 1024,
    }).trim();
  } catch (error) {
    if (allowFailure) return null;
    const detail = error.stderr?.toString().trim() || error.message;
    throw new Error(`${command} ${args.join(" ")} failed: ${detail}`);
  }
}

function runJson(command, args, cwd) {
  const output = run(command, args, cwd);
  return output ? JSON.parse(output) : null;
}

function repositoryName(raw) {
  return raw.nameWithOwner ?? raw.repository ?? raw.name;
}

export class LiveClient {
  constructor({ cwd, repository, defaultBranch }) {
    this.cwd = cwd;
    this.repository = repository;
    this.defaultBranch = defaultBranch;
  }

  static create({ cwd = process.cwd(), repository = null } = {}) {
    const args = repository
      ? ["repo", "view", repository, "--json", "nameWithOwner,defaultBranchRef"]
      : ["repo", "view", "--json", "nameWithOwner,defaultBranchRef"];
    const raw = runJson("gh", args, cwd);
    return new LiveClient({
      cwd,
      repository: repositoryName(raw),
      defaultBranch: raw.defaultBranchRef?.name ?? "main",
    });
  }

  async getIssue(number) {
    return runJson(
      "gh",
      ["issue", "view", String(number), "--repo", this.repository, "--json", ISSUE_FIELDS],
      this.cwd,
    );
  }

  async searchIssuesReferencing(number) {
    return runJson(
      "gh",
      [
        "issue",
        "list",
        "--repo",
        this.repository,
        "--state",
        "all",
        "--search",
        `#${number} in:body`,
        "--limit",
        "100",
        "--json",
        ISSUE_FIELDS,
      ],
      this.cwd,
    );
  }

  async listCandidates() {
    const base = [
      "issue",
      "list",
      "--repo",
      this.repository,
      "--state",
      "open",
      "--limit",
      "10",
      "--json",
      "number,title,state,url,updatedAt,author,assignees,parent",
    ];
    const authored = runJson("gh", [...base, "--author", "@me"], this.cwd);
    const assigned = runJson("gh", [...base, "--assignee", "@me"], this.cwd);
    return mergeCandidates(authored, assigned);
  }

  listPullRequests() {
    return runJson(
      "gh",
      [
        "pr",
        "list",
        "--repo",
        this.repository,
        "--state",
        "all",
        "--limit",
        "200",
        "--json",
        PR_FIELDS,
      ],
      this.cwd,
    );
  }
}

function mergeCandidates(...groups) {
  const candidates = new Map();
  for (const issue of groups.flat()) {
    const current = candidates.get(issue.number);
    if (!current || String(issue.updatedAt) > String(current.updatedAt)) {
      candidates.set(issue.number, issue);
    }
  }
  return [...candidates.values()]
    .sort((left, right) => String(right.updatedAt).localeCompare(String(left.updatedAt)))
    .slice(0, 10);
}

function parseWorktrees(output, cwd) {
  if (!output) return [];
  const blocks = output.split(/\n\n+/);
  return blocks
    .map((block) => {
      const record = {};
      for (const line of block.split("\n")) {
        const separator = line.indexOf(" ");
        const key = separator === -1 ? line : line.slice(0, separator);
        const value = separator === -1 ? true : line.slice(separator + 1);
        record[key] = value;
      }
      if (!record.worktree) return null;
      const branch = String(record.branch ?? "").replace(/^refs\/heads\//, "") || null;
      const status = run("git", ["-C", record.worktree, "status", "--porcelain"], cwd, {
        allowFailure: true,
      });
      return {
        path: record.worktree,
        branch,
        dirty: status === null ? null : status.length > 0,
      };
    })
    .filter(Boolean);
}

function parseBranches(output) {
  if (!output) return [];
  return output
    .split("\n")
    .map((name) => name.trim())
    .filter((name) => name && name !== "origin/HEAD")
    .map((name) => ({ name, remote: name.startsWith("origin/") }));
}

export function collectLiveWorkState(client, { includePullRequests = true } = {}) {
  const cwd = client.cwd;
  const branchOutput = run(
    "git",
    ["for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes/origin"],
    cwd,
    { allowFailure: true },
  );
  const worktreeOutput = run("git", ["worktree", "list", "--porcelain"], cwd, {
    allowFailure: true,
  });
  const currentBranch = run("git", ["branch", "--show-current"], cwd, {
    allowFailure: true,
  });

  return {
    currentBranch: currentBranch || null,
    branches: parseBranches(branchOutput),
    worktrees: parseWorktrees(worktreeOutput, cwd),
    pullRequests: includePullRequests ? client.listPullRequests() : [],
  };
}

export function inferIssueNumber(workState) {
  const values = [workState.currentBranch].filter(Boolean);

  const numbers = new Set();
  for (const value of values) {
    for (const pattern of [
      /(?:^|[/_-])issue[-/](\d+)(?:[-/_]|$)/gi,
      /(?:^|[/_-])integration[/_-](\d+)(?:[-/_]|$)/gi,
    ]) {
      for (const match of value.matchAll(pattern)) numbers.add(Number(match[1]));
    }
  }
  return numbers.size === 1 ? [...numbers][0] : null;
}

export function loadFixture(path) {
  const data = JSON.parse(readFileSync(path, "utf8"));
  const issues = new Map((data.issues ?? []).map((issue) => [Number(issue.number), issue]));
  const viewer = data.viewer?.login ?? data.viewer ?? null;

  const client = {
    repository: repositoryName(data.repository ?? {}),
    defaultBranch: data.repository?.defaultBranch ?? data.defaultBranch ?? "main",
    async getIssue(number) {
      const issue = issues.get(Number(number));
      if (!issue) throw new Error(`Fixture does not contain issue #${number}.`);
      return issue;
    },
    async searchIssuesReferencing(number) {
      return [...issues.values()].filter((issue) =>
        issueReferences(issue.body ?? "").includes(Number(number)),
      );
    },
    async listCandidates() {
      return mergeCandidates(
        [...issues.values()].filter(
          (issue) =>
            String(issue.state ?? "OPEN").toUpperCase() === "OPEN" &&
            (issue.author?.login ?? issue.author) === viewer,
        ),
        [...issues.values()].filter(
          (issue) =>
            String(issue.state ?? "OPEN").toUpperCase() === "OPEN" &&
            (issue.assignees?.nodes ?? issue.assignees ?? []).some(
              (assignee) => (assignee.login ?? assignee) === viewer,
            ),
        ),
      );
    },
  };

  return {
    client,
    workState: {
      currentBranch: data.currentBranch ?? null,
      branches: data.branches ?? [],
      worktrees: data.worktrees ?? [],
      pullRequests: data.pullRequests ?? [],
    },
  };
}
