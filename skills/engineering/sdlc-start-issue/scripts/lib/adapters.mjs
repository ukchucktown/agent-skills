import { execFileSync } from "node:child_process";
import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";

export class GitHubStartAdapter {
  constructor(repositoryRoot, repository, runner = execFileSync) {
    this.repositoryRoot = repositoryRoot;
    this.repository = repository;
    this.runner = runner;
  }

  gh(argumentsList) {
    return this.runner("gh", argumentsList, {
      cwd: this.repositoryRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      shell: false,
    });
  }

  async execute(operation, parameters) {
    if (operation === "assign-issue") {
      this.gh([
        "api", "--method", "POST",
        `repos/${this.repository}/issues/${parameters.issue}/assignees`,
        "-f", `assignees[]=${parameters.assignee}`,
      ]);
      return { assignee: parameters.assignee };
    }
    if (operation === "unassign-issue") {
      this.gh([
        "api", "--method", "DELETE",
        `repos/${this.repository}/issues/${parameters.issue}/assignees`,
        "-f", `assignees[]=${parameters.assignee}`,
      ]);
      return { unassigned: parameters.assignee };
    }
    if (operation === "remove-label") {
      this.gh([
        "api", "--method", "DELETE",
        `repos/${this.repository}/issues/${parameters.issue}/labels/${encodeURIComponent(parameters.label)}`,
      ]);
      return { removed: parameters.label };
    }
    if (operation === "comment") {
      const result = JSON.parse(this.gh([
        "api", "--method", "POST",
        `repos/${this.repository}/issues/${parameters.issue}/comments`,
        "-f", `body=${parameters.body}`,
      ]));
      return { id: result.id, url: result.html_url };
    }
    throw new Error(`unsupported GitHub start operation '${operation}'`);
  }
}

class CommandWorktreeAdapter {
  constructor(repositoryRoot, runner = execFileSync) {
    this.repositoryRoot = repositoryRoot;
    this.runner = runner;
  }

  command(executable, argumentsList, cwd = this.repositoryRoot) {
    return this.runner(executable, argumentsList, {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      shell: false,
    });
  }
}

export class SupacodeWorktreeAdapter extends CommandWorktreeAdapter {
  async execute(operation, parameters) {
    if (operation !== "create") throw new Error(`unsupported Supacode operation '${operation}'`);
    await mkdir(parameters.location, { recursive: true });
    const repositoryId = encodeURIComponent(`${resolve(parameters.repositoryRoot)}/`);
    const output = this.command("supacode", [
      "repo", "worktree-new",
      "-r", repositoryId,
      "--branch", parameters.branch,
      "--base", parameters.base,
      "--fetch",
      "--location", parameters.location,
      "--name", parameters.name,
      "--background",
    ]).trim();
    if (!output) throw new Error("Supacode did not return a worktree ID");
    return {
      id: output.split(/\r?\n/).at(-1),
      root: parameters.root,
      branch: parameters.branch,
      manager: "supacode",
    };
  }
}

export class GitWorktreeAdapter extends CommandWorktreeAdapter {
  async execute(operation, parameters) {
    if (operation !== "create") throw new Error(`unsupported Git worktree operation '${operation}'`);
    await mkdir(parameters.location, { recursive: true });
    if (parameters.fetchBranch) {
      this.command("git", ["fetch", "origin", parameters.fetchBranch]);
    }
    this.command("git", [
      "worktree", "add", "-b", parameters.branch, parameters.root, parameters.base,
    ]);
    return {
      id: parameters.root,
      root: parameters.root,
      branch: parameters.branch,
      manager: "git",
    };
  }
}
