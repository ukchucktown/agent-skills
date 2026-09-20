import { lstat, mkdir, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import { dirname, relative, resolve, sep } from "node:path";

import { repositoryDefaults, validateRepositoryConfig } from "../../../sdlc-workflow/scripts/lib/config.mjs";
import { fingerprint } from "../../../sdlc-workflow/scripts/lib/json.mjs";
import { validateAction } from "../../../sdlc-workflow/scripts/lib/plan.mjs";

export const instructionStart = "<!-- agent-skills:sdlc:start -->";
export const instructionEnd = "<!-- agent-skills:sdlc:end -->";

export const labelDefinitions = Object.freeze([
  {
    key: "featureLabel",
    color: "5319E7",
    description: "Parent feature managed by the SDLC workflow",
  },
  {
    key: "childLabel",
    color: "1D76DB",
    description: "Child issue in a coordinated feature",
  },
  {
    key: "readyLabel",
    color: "0E8A16",
    description: "Ready for an agent to implement",
  },
]);

export const managedPaths = Object.freeze([
  "AGENTS.md",
  "CLAUDE.md",
  ".github/copilot-instructions.md",
  "docs/agents/sdlc.md",
  ".github/workflows/sdlc-contract.yml",
  ".github/workflows/sdlc-close-child.yml",
  ".github/scripts/sdlc-contract-lib.mjs",
  ".github/scripts/sdlc-pr-contract.mjs",
  ".github/scripts/sdlc-close-child.mjs",
]);

const agentsBlock = `${instructionStart}
## Coordinated feature workflow

Use the installed \`sdlc-*\` skills for coordinated GitHub features. Read
\`docs/agents/sdlc.md\` for this repository's branch, label, validation, and
merge settings. Keep ordinary issue and pull request work on the repository's
existing workflow.
${instructionEnd}`;

const claudeBlock = `${instructionStart}
@AGENTS.md
${instructionEnd}`;

const copilotBlock = `${instructionStart}
Read and follow the repository workflow in \`/AGENTS.md\` and the SDLC settings
in \`/docs/agents/sdlc.md\`.
${instructionEnd}`;

function replaceMarkedBlock(current, block) {
  const text = current ?? "";
  const start = text.indexOf(instructionStart);
  const end = text.indexOf(instructionEnd);
  if ((start === -1) !== (end === -1) || (start !== -1 && end < start)) {
    throw new Error("an SDLC instruction marker is incomplete");
  }
  if (start !== -1) {
    if (text.indexOf(instructionStart, start + instructionStart.length) !== -1 ||
        text.indexOf(instructionEnd, end + instructionEnd.length) !== -1) {
      throw new Error("multiple SDLC instruction blocks need manual repair");
    }
    return `${text.slice(0, start)}${block}${text.slice(end + instructionEnd.length)}`;
  }
  const prefix = text && !text.endsWith("\n") ? `${text}\n` : text;
  return `${prefix}${prefix ? "\n" : ""}${block}\n`;
}

function claudeDocument(current) {
  if (current && /^@AGENTS\.md\s*$/m.test(current) && !current.includes(instructionStart)) {
    return current;
  }
  return replaceMarkedBlock(current, claudeBlock);
}

function yamlValue(value) {
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return JSON.stringify(value);
}

function existingBody(markdown) {
  if (!markdown?.startsWith("---")) return markdown?.trim() ? markdown : null;
  const normalized = markdown.replaceAll("\r\n", "\n");
  const end = normalized.indexOf("\n---\n", 3);
  return end === -1 ? null : normalized.slice(end + 5).replace(/^\n+/, "");
}

export function renderRepositoryDocument(settings, existing) {
  const config = validateRepositoryConfig({ ...repositoryDefaults, ...settings });
  const order = [
    "schemaVersion",
    "provider",
    "stableBranch",
    "integrationBranchPattern",
    "childBranchPattern",
    "worktreeRetention",
    "closeChildOnIntegrationMerge",
    "autoMergeChildPullRequests",
    "childMergeMethod",
    "featureMergeMethod",
    "validationSetupCommands",
    "childValidationCommands",
    "featureValidationCommands",
    "finalMergeApproval",
    "featureLabel",
    "childLabel",
    "readyLabel",
  ];
  const frontmatter = order.map((key) => `${key}: ${yamlValue(config[key])}`).join("\n");
  const body = existingBody(existing) ?? `# SDLC workflow

This repository uses coordinated feature branches for large efforts. GitHub
issues and native dependencies hold shared workflow state. Local worktrees and
agent harness settings remain machine preferences.

The root \`AGENTS.md\` contains the short instruction pointer. The installed
\`sdlc-*\` skills define the complete lifecycle.`;
  return `---\n${frontmatter}\n---\n\n${body.trim()}\n`;
}

function normalizeLabels(snapshot) {
  return {
    repository: snapshot.repository,
    labels: [...(snapshot.labels ?? [])]
      .map((label) => ({
        name: label.name,
        color: String(label.color ?? "").toUpperCase(),
        description: label.description ?? "",
      }))
      .sort((left, right) => left.name.localeCompare(right.name)),
  };
}

function mattDetections(files) {
  const locations = [];
  const pattern = /mattpocock|ask-matt|setup-matt-pocock-skills|to-tickets|grilling/i;
  for (const [file, content] of Object.entries(files)) {
    if (content && pattern.test(content)) locations.push(file);
  }
  return locations.sort();
}

function fileEvidence(files) {
  return Object.fromEntries(
    Object.entries(files)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([file, content]) => [file, content === null ? null : fingerprint(content)]),
  );
}

export function createSetupPlan({
  repositoryRoot,
  settings = {},
  files,
  labels,
  templates,
  mattLocations = [],
}) {
  const config = validateRepositoryConfig({ ...repositoryDefaults, ...settings });
  const desired = {
    "AGENTS.md": replaceMarkedBlock(files["AGENTS.md"], agentsBlock),
    "CLAUDE.md": claudeDocument(files["CLAUDE.md"]),
    ".github/copilot-instructions.md": replaceMarkedBlock(
      files[".github/copilot-instructions.md"],
      copilotBlock,
    ),
    "docs/agents/sdlc.md": renderRepositoryDocument(config, files["docs/agents/sdlc.md"]),
    ...templates,
  };
  const actions = [];
  for (const file of managedPaths) {
    if (typeof desired[file] !== "string") {
      throw new Error(`setup template '${file}' is missing`);
    }
    if (desired[file] !== files[file]) {
      actions.push({
        id: `write-${file.replace(/[^a-z0-9]+/gi, "-").replace(/^-|-$/g, "")}`,
        adapter: "filesystem",
        operation: "write-file",
        parameters: { path: file, content: desired[file] },
      });
    }
  }

  const normalizedLabels = normalizeLabels(labels);
  for (const definition of labelDefinitions) {
    const wanted = {
      name: config[definition.key],
      color: definition.color,
      description: definition.description,
    };
    const current = normalizedLabels.labels.find((label) => label.name === wanted.name);
    if (!current || current.color !== wanted.color || current.description !== wanted.description) {
      actions.push({
        id: `label-${definition.key}`,
        adapter: "github",
        operation: "ensure-label",
        parameters: wanted,
      });
    }
  }
  for (const [index, action] of actions.entries()) validateAction(action, index);

  const evidence = {
    files: fileEvidence(files),
    labels: fingerprint(normalizedLabels),
  };
  const content = {
    schemaVersion: 1,
    operation: "sdlc-setup",
    repositoryRoot: resolve(repositoryRoot),
    repository: normalizedLabels.repository,
    settings: config,
    detections: {
      mattConfiguration: [...new Set([...mattDetections(files), ...mattLocations])].sort(),
    },
    evidence: { ...evidence, fingerprint: fingerprint(evidence) },
    actions,
  };
  return { ...content, planId: fingerprint(content) };
}

export async function snapshotFiles(fileAdapter) {
  const entries = await Promise.all(
    managedPaths.map(async (file) => [file, await fileAdapter.read(file)]),
  );
  return Object.fromEntries(entries);
}

export async function applySetupPlan({ plan, fileAdapter, githubAdapter }) {
  const files = await snapshotFiles(fileAdapter);
  const labels = normalizeLabels(await githubAdapter.snapshot());
  const evidence = { files: fileEvidence(files), labels: fingerprint(labels) };
  if (fingerprint(evidence) !== plan.evidence?.fingerprint) {
    throw new Error("setup plan is stale; create and review a new plan");
  }
  const planContent = { ...plan };
  delete planContent.planId;
  if (fingerprint(planContent) !== plan.planId) throw new Error("setup plan content does not match its planId");

  const receipts = [];
  for (const [index, rawAction] of plan.actions.entries()) {
    const action = validateAction(rawAction, index);
    if (action.adapter === "filesystem") {
      await fileAdapter.write(action.parameters.path, action.parameters.content);
    } else if (action.adapter === "github") {
      await githubAdapter.ensureLabel(action.parameters);
    } else {
      throw new Error(`setup cannot apply '${action.adapter}' actions`);
    }
    receipts.push({ actionId: action.id, status: "applied" });
  }
  return { schemaVersion: 1, planId: plan.planId, status: "applied", receipts };
}

export class NodeFileAdapter {
  constructor(repositoryRoot) {
    this.repositoryRoot = resolve(repositoryRoot);
  }

  resolve(file) {
    const target = resolve(this.repositoryRoot, file);
    const location = relative(this.repositoryRoot, target);
    if (location.startsWith(`..${sep}`) || location === "..") {
      throw new Error(`path '${file}' leaves the repository`);
    }
    return target;
  }

  async assertSafeParents(target) {
    let current = dirname(target);
    const parents = [];
    while (current !== this.repositoryRoot) {
      parents.push(current);
      const next = dirname(current);
      if (next === current) throw new Error(`path '${target}' has no repository parent`);
      current = next;
    }
    for (const parent of parents.reverse()) {
      try {
        const metadata = await lstat(parent);
        if (metadata.isSymbolicLink()) {
          throw new Error(`refusing symbolic link directory '${parent}'`);
        }
      } catch (error) {
        if (error.code === "ENOENT") return;
        throw error;
      }
    }
  }

  async read(file) {
    const target = this.resolve(file);
    await this.assertSafeParents(target);
    try {
      const metadata = await lstat(target);
      if (metadata.isSymbolicLink()) throw new Error(`refusing symbolic link '${file}'`);
      return await readFile(target, "utf8");
    } catch (error) {
      if (error.code === "ENOENT") return null;
      throw error;
    }
  }

  async write(file, content) {
    if (typeof content !== "string") throw new Error(`file '${file}' content must be a string`);
    const target = this.resolve(file);
    await this.assertSafeParents(target);
    try {
      const metadata = await lstat(target);
      if (metadata.isSymbolicLink()) throw new Error(`refusing symbolic link '${file}'`);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    await mkdir(dirname(target), { recursive: true });
    const temporary = `${target}.sdlc-${process.pid}.tmp`;
    try {
      await writeFile(temporary, content, { encoding: "utf8", flag: "wx" });
      await rm(target, { force: true });
      await rename(temporary, target);
    } finally {
      await rm(temporary, { force: true });
    }
  }

  async detectMattConfiguration() {
    const known = new Set([
      "ask-matt",
      "grilling",
      "to-tickets",
      "wayfinder",
      "setup-matt-pocock-skills",
      "improve-codebase-architecture",
    ]);
    const locations = [];
    for (const directory of [".agents/skills", ".claude/skills", ".github/skills"]) {
      const target = this.resolve(directory);
      await this.assertSafeParents(target);
      try {
        const metadata = await lstat(target);
        if (metadata.isSymbolicLink()) {
          throw new Error(`refusing symbolic link directory '${directory}'`);
        }
        for (const entry of await readdir(target, { withFileTypes: true })) {
          if (known.has(entry.name)) locations.push(`${directory}/${entry.name}`);
        }
      } catch (error) {
        if (error.code !== "ENOENT") throw error;
      }
    }
    return locations.sort();
  }
}
