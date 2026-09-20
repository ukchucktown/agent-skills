import { execFileSync } from "node:child_process";

import {
  recordedBranch,
  renderPattern,
} from "../../../sdlc-workflow/scripts/lib/config.mjs";

function names(values = [], field) {
  return values.map((value) => typeof value === "string" ? value : value[field]);
}

function checks(values = []) {
  if (values.length === 0) return "pending";
  const states = values.map((check) => String(check.conclusion ?? check.state ?? check.status).toLowerCase());
  if (states.some((state) => new Set(["failure", "failed", "error", "cancelled", "timed_out"]).has(state))) {
    return "failing";
  }
  if (states.every((state) => new Set(["success", "neutral", "skipped"]).has(state))) {
    return "passing";
  }
  return "pending";
}

function review(value) {
  if (value === "APPROVED") return "approved";
  if (value === "CHANGES_REQUESTED") return "changes_requested";
  return "pending";
}

export class LiveGitHubAdapter {
  constructor(repositoryRoot, config, runner = execFileSync) {
    this.repositoryRoot = repositoryRoot;
    this.config = config;
    this.runner = runner;
    this.repository = null;
  }

  gh(argumentsList) {
    return this.runner("gh", argumentsList, {
      cwd: this.repositoryRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      shell: false,
    });
  }

  repositoryName() {
    if (!this.repository) {
      this.repository = JSON.parse(this.gh(["repo", "view", "--json", "nameWithOwner"])).nameWithOwner;
    }
    return this.repository;
  }

  api(endpoint) {
    return JSON.parse(this.gh([
      "api", "-H", "X-GitHub-Api-Version: 2026-03-10", endpoint,
    ]));
  }

  branchExists(repository, branch) {
    try {
      this.api(`repos/${repository}/branches/${encodeURIComponent(branch)}`);
      return true;
    } catch (error) {
      if (String(error.stderr ?? error.message).includes("404")) return false;
      throw error;
    }
  }

  async featureNumbers(explicit) {
    if (explicit) return [explicit];
    const features = JSON.parse(this.gh([
      "issue", "list", "--repo", this.repositoryName(), "--state", "open",
      "--label", this.config.featureLabel, "--limit", "100", "--json", "number",
    ]));
    return features.map((feature) => feature.number).sort((left, right) => left - right);
  }

  async snapshot(featureNumber) {
    const repository = this.repositoryName();
    const feature = this.api(`repos/${repository}/issues/${featureNumber}`);
    const children = this.api(`repos/${repository}/issues/${featureNumber}/sub_issues?per_page=100`);
    const featureComments = this.api(
      `repos/${repository}/issues/${featureNumber}/comments?per_page=100`,
    );
    const integrationBranch = recordedBranch(featureComments, "integration") ?? renderPattern(
      this.config.integrationBranchPattern,
      feature.number,
      feature.title,
    );
    const issues = [{
      number: feature.number,
      role: "feature",
      state: feature.state,
      title: feature.title,
      labels: names(feature.labels, "name"),
      assignees: names(feature.assignees, "login"),
      blockedBy: [],
      branch: integrationBranch,
    }];

    for (const child of children) {
      const blockers = this.api(
        `repos/${repository}/issues/${child.number}/dependencies/blocked_by?per_page=100`,
      );
      const comments = this.api(`repos/${repository}/issues/${child.number}/comments?per_page=100`);
      const branch = recordedBranch(comments) ?? renderPattern(
        this.config.childBranchPattern,
        child.number,
        child.title,
      );
      const hasBranch = this.branchExists(repository, branch);
      const pullRequests = JSON.parse(this.gh([
        "pr", "list", "--repo", repository, "--state", "all", "--head", branch,
        "--limit", "20",
        "--json", "number,state,baseRefName,headRefName,headRefOid,statusCheckRollup,reviewDecision",
      ]));
      const pullRequest = pullRequests.find((pull) => pull.state === "OPEN") ??
        pullRequests.find((pull) => pull.state === "MERGED") ?? pullRequests[0];
      issues.push({
        number: child.number,
        role: "child",
        parent: feature.number,
        state: child.state,
        title: child.title,
        labels: names(child.labels, "name"),
        assignees: names(child.assignees, "login"),
        blockedBy: blockers.map((blocker) => blocker.number),
        ...(hasBranch ? { branch } : {}),
        ...(pullRequest ? {
          pullRequest: {
            number: pullRequest.number,
            state: pullRequest.state,
            base: pullRequest.baseRefName,
            head: pullRequest.headRefName,
            headSha: pullRequest.headRefOid,
            checks: checks(pullRequest.statusCheckRollup),
            review: review(pullRequest.reviewDecision),
          },
        } : {}),
      });
    }
    return { schemaVersion: 1, repository, issues };
  }
}

export class GitWorktreeSnapshotAdapter {
  constructor(repositoryRoot, runner = execFileSync) {
    this.repositoryRoot = repositoryRoot;
    this.runner = runner;
  }

  async snapshot() {
    const output = this.runner("git", ["worktree", "list", "--porcelain"], {
      cwd: this.repositoryRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      shell: false,
    });
    const worktrees = [];
    let current = null;
    for (const line of output.replaceAll("\r\n", "\n").split("\n")) {
      if (line.startsWith("worktree ")) {
        if (current) worktrees.push(current);
        current = { id: line.slice(9), root: line.slice(9), status: "active" };
      } else if (line.startsWith("branch ") && current) {
        current.branch = line.slice(7).replace(/^refs\/heads\//, "");
      } else if (line === "detached" && current) {
        current.status = "detached";
      }
    }
    if (current) worktrees.push(current);
    for (const worktree of worktrees) {
      const match = worktree.branch?.match(/(?:^|\/)issue-([1-9][0-9]*)(?:-|$)/);
      if (match) worktree.issue = Number(match[1]);
    }
    return { schemaVersion: 1, worktrees };
  }
}
