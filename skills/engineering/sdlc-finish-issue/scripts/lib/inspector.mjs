import { execFileSync } from "node:child_process";

import {
  recordedBranch,
  renderPattern,
} from "../../../sdlc-workflow/scripts/lib/config.mjs";

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

export class FinishInspector {
  constructor(repositoryRoot, repositoryConfig, runner = execFileSync) {
    this.repositoryRoot = repositoryRoot;
    this.repositoryConfig = repositoryConfig;
    this.runner = runner;
    this.repository = null;
  }

  command(executable, argumentsList) {
    return this.runner(executable, argumentsList, {
      cwd: this.repositoryRoot,
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
      "--limit", "20",
      "--json", "number,state,baseRefName,headRefName,headRefOid,title,body,url,reviewDecision,statusCheckRollup,mergeable,isDraft",
    ])).map((pull) => ({
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
    })).sort((left, right) => left.number - right.number);

    return {
      schemaVersion: 1,
      repository,
      issue: {
        number: issue.number,
        state: issue.state,
        title: issue.title,
        labels: names(issue.labels, "name"),
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
      branch,
      integrationBranch,
      integrationBranchExists: this.branchExists(repository, integrationBranch),
      currentBranch: this.command("git", ["branch", "--show-current"]).trim(),
      candidateCommit: this.command("git", ["rev-parse", "HEAD"]).trim(),
      clean: this.command("git", ["status", "--porcelain", "--untracked-files=normal"]).trim() === "",
      pullRequests,
    };
  }
}
