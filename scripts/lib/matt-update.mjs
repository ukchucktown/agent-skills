import { execFileSync } from "node:child_process";

import { stableJson } from "../../skills/engineering/sdlc-workflow/scripts/lib/json.mjs";

export function validateMattManifest(value) {
  if (!value || value.schemaVersion !== 1) throw new Error("Matt dependency needs schemaVersion 1");
  if (!/^[^/]+\/[^/]+$/.test(value.repository ?? "")) {
    throw new Error("Matt dependency repository must be owner/name");
  }
  if (typeof value.branch !== "string" || !value.branch) throw new Error("Matt dependency needs a branch");
  if (!/^[a-f0-9]{40}$/.test(value.revision ?? "")) {
    throw new Error("Matt dependency revision must be a full commit SHA");
  }
  if (!value.skills || typeof value.skills !== "object" || Array.isArray(value.skills)) {
    throw new Error("Matt dependency needs selected skills");
  }
  const skills = Object.entries(value.skills).sort(([left], [right]) => left.localeCompare(right));
  if (skills.length === 0) throw new Error("Matt dependency needs at least one selected skill");
  for (const [name, path] of skills) {
    if (!/^[a-z0-9-]+$/.test(name)) throw new Error(`invalid Matt skill name '${name}'`);
    if (typeof path !== "string" || !path.endsWith(`/${name}`)) {
      throw new Error(`Matt skill '${name}' has an invalid source path`);
    }
  }
  return {
    schemaVersion: 1,
    repository: value.repository,
    branch: value.branch,
    revision: value.revision,
    skills: Object.fromEntries(skills),
  };
}

export function validateUpstreamSkill(name, content) {
  const normalized = String(content).replaceAll("\r\n", "\n");
  if (!normalized.startsWith("---\n")) throw new Error(`Matt skill '${name}' has no frontmatter`);
  const end = normalized.indexOf("\n---\n", 4);
  if (end === -1) throw new Error(`Matt skill '${name}' has incomplete frontmatter`);
  const match = normalized.slice(4, end).match(/^name:\s*['"]?([^'"\n]+)['"]?\s*$/m);
  if (!match || match[1].trim() !== name) {
    throw new Error(`Matt skill '${name}' frontmatter name changed`);
  }
  return true;
}

export function updateMattManifest(manifest, revision) {
  const current = validateMattManifest(manifest);
  if (!/^[a-f0-9]{40}$/.test(revision)) throw new Error("new Matt revision must be a full commit SHA");
  return { ...current, revision };
}

export class GitHubMattUpdater {
  constructor(repositoryRoot, runner = execFileSync) {
    this.repositoryRoot = repositoryRoot;
    this.runner = runner;
  }

  gh(argumentsList, input) {
    return this.runner("gh", argumentsList, {
      cwd: this.repositoryRoot,
      encoding: "utf8",
      stdio: [input === undefined ? "ignore" : "pipe", "pipe", "pipe"],
      shell: false,
      ...(input === undefined ? {} : { input: JSON.stringify(input) }),
    });
  }

  api(endpoint, method = "GET", input) {
    const args = ["api"];
    if (method !== "GET") args.push("--method", method);
    args.push(endpoint);
    if (input !== undefined) args.push("--input", "-");
    return JSON.parse(this.gh(args, input));
  }

  latestRevision(manifest) {
    return this.api(`repos/${manifest.repository}/commits/${encodeURIComponent(manifest.branch)}`).sha;
  }

  verifyRevision(manifest, revision) {
    for (const [name, path] of Object.entries(manifest.skills)) {
      const value = this.api(
        `repos/${manifest.repository}/contents/${path}/SKILL.md?ref=${revision}`,
      );
      const content = Buffer.from(value.content, "base64").toString("utf8");
      validateUpstreamSkill(name, content);
    }
  }

  createPullRequest(manifest, updated, file = "dependencies/mattpocock.json") {
    const repository = JSON.parse(this.gh([
      "repo", "view", "--json", "nameWithOwner,defaultBranchRef",
    ]));
    const branch = `chore/update-matt-${updated.revision.slice(0, 7)}`;
    const existing = JSON.parse(this.gh([
      "pr", "list", "--repo", repository.nameWithOwner, "--state", "all", "--head", branch,
      "--json", "number,state,url", "--limit", "1",
    ]));
    if (existing.length > 0) return { status: "existing", ...existing[0], branch };

    const baseBranch = repository.defaultBranchRef.name;
    const base = this.api(`repos/${repository.nameWithOwner}/git/ref/heads/${encodeURIComponent(baseBranch)}`);
    const baseCommit = this.api(`repos/${repository.nameWithOwner}/git/commits/${base.object.sha}`);
    const blob = this.api(`repos/${repository.nameWithOwner}/git/blobs`, "POST", {
      content: stableJson(updated),
      encoding: "utf-8",
    });
    const tree = this.api(`repos/${repository.nameWithOwner}/git/trees`, "POST", {
      base_tree: baseCommit.tree.sha,
      tree: [{ path: file, mode: "100644", type: "blob", sha: blob.sha }],
    });
    const commit = this.api(`repos/${repository.nameWithOwner}/git/commits`, "POST", {
      message: `Update Matt Pocock skills to ${updated.revision.slice(0, 7)}`,
      tree: tree.sha,
      parents: [base.object.sha],
    });
    this.api(`repos/${repository.nameWithOwner}/git/refs`, "POST", {
      ref: `refs/heads/${branch}`,
      sha: commit.sha,
    });
    const url = this.gh([
      "pr", "create", "--repo", repository.nameWithOwner,
      "--base", baseBranch,
      "--head", branch,
      "--title", `Update Matt Pocock skills to ${updated.revision.slice(0, 7)}`,
      "--body", [
        `Updates the tested Matt Pocock skills revision from \`${manifest.revision}\` to \`${updated.revision}\`.`,
        "",
        "The update command verified every selected skill path and frontmatter name at the new revision.",
      ].join("\n"),
    ]).trim();
    return { status: "created", url, branch, commit: commit.sha };
  }
}

export function renderMattManifest(value) {
  return stableJson(validateMattManifest(value));
}
