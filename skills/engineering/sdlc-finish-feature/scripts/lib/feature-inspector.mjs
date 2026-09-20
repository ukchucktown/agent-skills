import { execFileSync } from "node:child_process";

import {
  recordedBranch,
  renderPattern,
} from "../../../sdlc-workflow/scripts/lib/config.mjs";
import { GitWorktreeSnapshotAdapter } from "../../../sdlc-status/scripts/lib/live-adapters.mjs";

function names(values = [], field) {
  return values.map((value) => typeof value === "string" ? value : value[field]).sort();
}

function normalizeCheck(check) {
  return {
    name: check.name ?? check.context ?? "unknown",
    status: check.status ?? (check.state ? "COMPLETED" : ""),
    conclusion: check.conclusion ?? check.state ?? "",
  };
}

function normalizePull(pull) {
  return {
    number: pull.number,
    state: pull.state,
    base: pull.baseRefName,
    head: pull.headRefName,
    headSha: pull.headRefOid,
    title: pull.title,
    body: pull.body,
    url: pull.url,
    reviewDecision: pull.reviewDecision,
    checks: (pull.statusCheckRollup ?? []).map(normalizeCheck),
    mergeable: pull.mergeable,
    isDraft: pull.isDraft,
  };
}

export class FeatureInspector {
  constructor(repositoryRoot, repositoryConfig, runner = execFileSync) {
    this.repositoryRoot = repositoryRoot;
    this.repositoryConfig = repositoryConfig;
    this.runner = runner;
    this.repository = null;
  }

  command(executable, argumentsList, cwd = this.repositoryRoot) {
    return this.runner(executable, argumentsList, {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      shell: false,
    });
  }

  gh(argumentsList) {
    return this.command("gh", argumentsList);
  }

  api(endpoint) {
    return JSON.parse(this.gh([
      "api", "-H", "X-GitHub-Api-Version: 2026-03-10", endpoint,
    ]));
  }

  repositoryName() {
    if (!this.repository) {
      this.repository = JSON.parse(this.gh(["repo", "view", "--json", "nameWithOwner"])).nameWithOwner;
    }
    return this.repository;
  }

  pulls(repository, branch) {
    return JSON.parse(this.gh([
      "pr", "list", "--repo", repository, "--state", "all", "--head", branch,
      "--limit", "20",
      "--json", "number,state,baseRefName,headRefName,headRefOid,title,body,url,reviewDecision,statusCheckRollup,mergeable,isDraft",
    ])).map(normalizePull).sort((left, right) => left.number - right.number);
  }

  clean(path) {
    try {
      return this.command("git", ["status", "--porcelain", "--untracked-files=normal"], path).trim() === "";
    } catch {
      return false;
    }
  }

  mergedToStable(branch, stableBranch) {
    try {
      this.command("git", ["merge-base", "--is-ancestor", branch, stableBranch]);
      return true;
    } catch {
      return false;
    }
  }

  async inspect(featureNumber) {
    const repository = this.repositoryName();
    const parent = this.api(`repos/${repository}/issues/${featureNumber}`);
    const parentComments = this.api(`repos/${repository}/issues/${featureNumber}/comments?per_page=100`);
    const integrationBranch = recordedBranch(parentComments, "integration") ?? renderPattern(
      this.repositoryConfig.integrationBranchPattern,
      parent.number,
      parent.title,
    );
    const childIssues = this.api(`repos/${repository}/issues/${featureNumber}/sub_issues?per_page=100`);
    const children = childIssues.map((child) => {
      const comments = this.api(`repos/${repository}/issues/${child.number}/comments?per_page=100`);
      const branch = recordedBranch(comments) ?? renderPattern(
        this.repositoryConfig.childBranchPattern,
        child.number,
        child.title,
      );
      return {
        number: child.number,
        state: child.state,
        title: child.title,
        labels: names(child.labels, "name"),
        branch,
        pullRequests: this.pulls(repository, branch),
      };
    }).sort((left, right) => left.number - right.number);
    const listed = await new GitWorktreeSnapshotAdapter(this.repositoryRoot, this.runner).snapshot();
    const worktrees = listed.worktrees.map((worktree) => ({
      path: worktree.root,
      branch: worktree.branch ?? null,
      clean: worktree.status === "active" && this.clean(worktree.root),
      mergedToStable: worktree.branch
        ? this.mergedToStable(worktree.branch, this.repositoryConfig.stableBranch)
        : false,
    })).sort((left, right) => left.path.localeCompare(right.path));
    const integrationWorktree = worktrees.find((worktree) => worktree.branch === integrationBranch) ?? null;
    const candidateCommit = integrationWorktree
      ? this.command("git", ["rev-parse", "HEAD"], integrationWorktree.path).trim()
      : null;

    return {
      schemaVersion: 1,
      repository,
      stableBranch: this.repositoryConfig.stableBranch,
      invocationBranch: this.command("git", ["branch", "--show-current"]).trim(),
      parent: {
        number: parent.number,
        state: parent.state,
        title: parent.title,
        labels: names(parent.labels, "name"),
      },
      children,
      integrationBranch,
      integrationWorktree,
      candidateCommit,
      finalPullRequests: this.pulls(repository, integrationBranch),
      worktrees,
    };
  }
}
