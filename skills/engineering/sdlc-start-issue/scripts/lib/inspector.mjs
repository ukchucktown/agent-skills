import { execFileSync } from "node:child_process";

import {
  recordedBranch,
  renderPattern,
} from "../../../sdlc-workflow/scripts/lib/config.mjs";
import { GitWorktreeSnapshotAdapter } from "../../../sdlc-status/scripts/lib/live-adapters.mjs";

function names(values = [], field) {
  return values.map((value) => typeof value === "string" ? value : value[field]).sort();
}

export class StartInspector {
  constructor(repositoryRoot, repositoryConfig, machineConfig, runner = execFileSync) {
    this.repositoryRoot = repositoryRoot;
    this.repositoryConfig = repositoryConfig;
    this.machineConfig = machineConfig;
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

  async inspect(issueNumber) {
    const repository = this.repositoryName();
    const issue = this.api(`repos/${repository}/issues/${issueNumber}`);
    const parent = this.api(`repos/${repository}/issues/${issueNumber}/parent`);
    const blockers = this.api(
      `repos/${repository}/issues/${issueNumber}/dependencies/blocked_by?per_page=100`,
    );
    const comments = this.api(`repos/${repository}/issues/${issueNumber}/comments?per_page=100`);
    const parentComments = this.api(`repos/${repository}/issues/${parent.number}/comments?per_page=100`);
    const actor = JSON.parse(this.gh(["api", "user"])).login;
    const integrationBranch = recordedBranch(parentComments, "integration") ?? renderPattern(
      this.repositoryConfig.integrationBranchPattern,
      parent.number,
      parent.title,
    );
    const branch = recordedBranch(comments) ?? renderPattern(
      this.repositoryConfig.childBranchPattern,
      issue.number,
      issue.title,
    );
    const pullRequests = JSON.parse(this.gh([
      "pr", "list", "--repo", repository, "--state", "all", "--head", branch,
      "--limit", "20", "--json", "number,state,url",
    ])).sort((left, right) => left.number - right.number);
    const worktreeSnapshot = await new GitWorktreeSnapshotAdapter(
      this.repositoryRoot,
      this.runner,
    ).snapshot();

    return {
      schemaVersion: 1,
      repository,
      actor,
      machine: {
        worktreeRoot: this.machineConfig.worktreeRoot,
        worktreeManager: this.machineConfig.worktreeManager,
      },
      issue: {
        number: issue.number,
        state: issue.state,
        title: issue.title,
        labels: names(issue.labels, "name"),
        assignees: names(issue.assignees, "login"),
      },
      parent: {
        number: parent.number,
        state: parent.state,
        title: parent.title,
        labels: names(parent.labels, "name"),
      },
      blockers: blockers
        .map((blocker) => ({ number: blocker.number, state: blocker.state, title: blocker.title }))
        .sort((left, right) => left.number - right.number),
      comments: comments
        .map((comment) => ({ id: comment.id, body: comment.body }))
        .sort((left, right) => left.id - right.id),
      pullRequests,
      branch,
      integrationBranch,
      integrationBranchExists: this.branchExists(repository, integrationBranch),
      branchExists: this.branchExists(repository, branch),
      worktrees: worktreeSnapshot.worktrees
        .filter((worktree) => worktree.branch === branch)
        .map((worktree) => ({ ...worktree, manager: this.machineConfig.worktreeManager })),
    };
  }
}
