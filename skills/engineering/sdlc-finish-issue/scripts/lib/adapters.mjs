import { execFileSync } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";

export class GitFinishAdapter {
  constructor(repositoryRoot, runner = execFileSync) {
    this.repositoryRoot = repositoryRoot;
    this.runner = runner;
  }

  async pushCandidate({ branch, candidateCommit }) {
    this.runner("git", ["push", "origin", `${candidateCommit}:refs/heads/${branch}`], {
      cwd: this.repositoryRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      shell: false,
    });
    return { branch, candidateCommit };
  }
}

function normalizeCheck(check) {
  return {
    name: check.name ?? check.context ?? "unknown",
    status: check.status ?? (check.state ? "COMPLETED" : ""),
    conclusion: check.conclusion ?? check.state ?? "",
  };
}

export class GitHubFinishAdapter {
  constructor(repositoryRoot, { runner = execFileSync, wait = delay, intervalMs = 10_000 } = {}) {
    this.repositoryRoot = repositoryRoot;
    this.runner = runner;
    this.wait = wait;
    this.intervalMs = intervalMs;
  }

  gh(argumentsList) {
    return this.runner("gh", argumentsList, {
      cwd: this.repositoryRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      shell: false,
    });
  }

  pullRequest(number) {
    const pull = JSON.parse(this.gh([
      "pr", "view", String(number),
      "--json", "number,state,baseRefName,headRefName,headRefOid,reviewDecision,statusCheckRollup,mergeable,isDraft,url",
    ]));
    return {
      number: pull.number,
      state: pull.state,
      base: pull.baseRefName,
      head: pull.headRefName,
      headSha: pull.headRefOid,
      reviewDecision: pull.reviewDecision,
      checks: (pull.statusCheckRollup ?? []).map(normalizeCheck),
      mergeable: pull.mergeable,
      isDraft: pull.isDraft,
      url: pull.url,
    };
  }

  async submitPullRequest(submission) {
    if (submission.operation === "create") {
      const url = this.gh([
        "pr", "create",
        "--base", submission.base,
        "--head", submission.head,
        "--title", submission.title,
        "--body", submission.body,
      ]).trim();
      const number = Number(url.split("/").at(-1));
      if (!Number.isInteger(number)) throw new Error("GitHub did not return a pull request number");
      return { number, url };
    }
    this.gh([
      "pr", "edit", String(submission.number),
      "--base", submission.base,
      "--title", submission.title,
      "--body", submission.body,
    ]);
    return { number: submission.number };
  }

  async waitForGates(expected) {
    let readyObservations = 0;
    for (let attempt = 0; attempt < 120; attempt += 1) {
      const pull = this.pullRequest(expected.number);
      const { evaluatePullRequestGates } = await import("./finisher.mjs");
      const gate = evaluatePullRequestGates(pull, expected);
      if (gate.status === "failed" || gate.status === "merged") return pull;
      if (gate.status === "ready") {
        readyObservations += 1;
        if (readyObservations >= 2) return pull;
      } else {
        readyObservations = 0;
      }
      await this.wait(this.intervalMs);
    }
    throw new Error(`timed out while waiting for pull request #${expected.number} gates`);
  }

  async mergePullRequest({ number, method, candidateCommit }) {
    this.gh([
      "pr", "merge", String(number), `--${method}`, "--match-head-commit", candidateCommit,
    ]);
    const pull = this.pullRequest(number);
    return { merged: pull.state === "MERGED", number };
  }

  async closeIssue(number) {
    const issue = JSON.parse(this.gh(["issue", "view", String(number), "--json", "state"]));
    if (issue.state === "OPEN") {
      this.gh(["issue", "close", String(number), "--reason", "completed"]);
    }
    return { number, state: "CLOSED" };
  }
}
