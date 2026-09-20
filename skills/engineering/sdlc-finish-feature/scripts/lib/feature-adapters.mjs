import { execFileSync } from "node:child_process";

import { GitHubFinishAdapter } from "../../../sdlc-finish-issue/scripts/lib/adapters.mjs";

export class FeatureGitAdapter {
  constructor(repositoryRoot, runner = execFileSync) {
    this.repositoryRoot = repositoryRoot;
    this.runner = runner;
  }

  command(argumentsList, cwd = this.repositoryRoot) {
    return this.runner("git", argumentsList, {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      shell: false,
    });
  }

  async pushCandidate({ root, branch, candidateCommit }) {
    this.command(["push", "origin", `${candidateCommit}:refs/heads/${branch}`], root);
    return { branch, candidateCommit };
  }
}

export class FeatureGitHubAdapter extends GitHubFinishAdapter {
  async closePullRequest(number) {
    this.gh(["pr", "close", String(number)]);
    return { type: "pull-request", number, state: "CLOSED" };
  }

  async closeIssue(number, reason = "completed") {
    const issue = JSON.parse(this.gh(["issue", "view", String(number), "--json", "state"]));
    if (issue.state === "OPEN") {
      this.gh(["issue", "close", String(number), "--reason", reason]);
    }
    return { type: "issue", number, state: "CLOSED", reason };
  }
}

export class GitCleanupAdapter {
  constructor(repositoryRoot, runner = execFileSync) {
    this.repositoryRoot = repositoryRoot;
    this.runner = runner;
  }

  command(argumentsList) {
    return this.runner("git", argumentsList, {
      cwd: this.repositoryRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      shell: false,
    });
  }

  remoteBranchExists(branch) {
    try {
      this.command(["ls-remote", "--exit-code", "--heads", "origin", `refs/heads/${branch}`]);
      return true;
    } catch {
      return false;
    }
  }

  async remove(worktree) {
    this.command(["worktree", "remove", worktree.path]);
    this.command(["branch", "--delete", "--force", worktree.branch]);
    if (this.remoteBranchExists(worktree.branch)) {
      this.command(["push", "origin", "--delete", worktree.branch]);
    }
    return { path: worktree.path, branch: worktree.branch, removed: true };
  }
}
