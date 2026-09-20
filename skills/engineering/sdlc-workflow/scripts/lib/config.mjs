import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { homedir } from "node:os";

export const repositoryDefaults = Object.freeze({
  schemaVersion: 1,
  provider: "github",
  stableBranch: "main",
  integrationBranchPattern: "integration/issue-{issue}-{slug}",
  childBranchPattern: "feat/issue-{issue}-{slug}",
  worktreeRetention: "feature",
  closeChildOnIntegrationMerge: true,
  autoMergeChildPullRequests: true,
  childMergeMethod: "squash",
  featureMergeMethod: "merge",
  validationSetupCommands: [],
  childValidationCommands: [],
  featureValidationCommands: [],
  finalMergeApproval: "required",
  featureLabel: "sdlc:feature",
  childLabel: "sdlc:child",
  readyLabel: "ready-for-agent",
});

function scalar(value) {
  const trimmed = value.trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }
  if (trimmed === "true") return true;
  if (trimmed === "false") return false;
  if (trimmed === "null") return null;
  if (/^-?\d+$/.test(trimmed)) return Number.parseInt(trimmed, 10);
  if (trimmed.startsWith("[") || trimmed.startsWith("{")) {
    try {
      return JSON.parse(trimmed);
    } catch {
      throw new Error(`invalid JSON value '${trimmed}'`);
    }
  }
  return trimmed;
}

export function parseFrontmatter(markdown, source = "configuration") {
  const normalized = markdown.replaceAll("\r\n", "\n");
  if (!normalized.startsWith("---\n")) {
    throw new Error(`${source} must start with YAML frontmatter`);
  }
  const end = normalized.indexOf("\n---\n", 4);
  if (end === -1) throw new Error(`${source} frontmatter has no closing delimiter`);

  const result = {};
  for (const [index, line] of normalized.slice(4, end).split("\n").entries()) {
    if (!line.trim() || line.trimStart().startsWith("#")) continue;
    if (/^\s/.test(line)) {
      throw new Error(`${source}:${index + 2} uses unsupported nested YAML`);
    }
    const separator = line.indexOf(":");
    if (separator < 1) throw new Error(`${source}:${index + 2} is not a key-value pair`);
    const key = line.slice(0, separator).trim();
    if (Object.hasOwn(result, key)) throw new Error(`${source} repeats '${key}'`);
    result[key] = scalar(line.slice(separator + 1));
  }
  return result;
}

function assertString(config, key) {
  if (typeof config[key] !== "string" || !config[key].trim()) {
    throw new Error(`repository configuration '${key}' must be a non-empty string`);
  }
}

export function validateRepositoryConfig(value) {
  const allowed = new Set(Object.keys(repositoryDefaults));
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) throw new Error(`repository configuration has unknown key '${key}'`);
  }

  const config = { ...repositoryDefaults, ...value };
  if (config.schemaVersion !== 1) {
    throw new Error(`unsupported repository schemaVersion '${config.schemaVersion}'`);
  }
  if (config.provider !== "github") throw new Error("provider must be 'github'");
  for (const key of [
    "stableBranch",
    "integrationBranchPattern",
    "childBranchPattern",
    "featureLabel",
    "childLabel",
    "readyLabel",
  ]) {
    assertString(config, key);
  }
  for (const key of ["integrationBranchPattern", "childBranchPattern"]) {
    if (!config[key].includes("{issue}") || !config[key].includes("{slug}")) {
      throw new Error(`repository configuration '${key}' needs {issue} and {slug}`);
    }
  }
  if (config.worktreeRetention !== "feature") {
    throw new Error("worktreeRetention must be 'feature'");
  }
  if (config.finalMergeApproval !== "required") {
    throw new Error("finalMergeApproval must be 'required'");
  }
  for (const key of ["closeChildOnIntegrationMerge", "autoMergeChildPullRequests"]) {
    if (typeof config[key] !== "boolean") {
      throw new Error(`repository configuration '${key}' must be a boolean`);
    }
  }
  for (const key of ["childMergeMethod", "featureMergeMethod"]) {
    if (!new Set(["merge", "squash", "rebase"]).has(config[key])) {
      throw new Error(`repository configuration '${key}' must be merge, squash, or rebase`);
    }
  }
  for (const key of [
    "validationSetupCommands",
    "childValidationCommands",
    "featureValidationCommands",
  ]) {
    if (!Array.isArray(config[key])) {
      throw new Error(`repository configuration '${key}' must be an array`);
    }
    config[key] = config[key].map((command, index) => {
      if (!command || typeof command !== "object" || Array.isArray(command)) {
        throw new Error(`repository configuration '${key}' item ${index + 1} must be an object`);
      }
      const commandKeys = Object.keys(command).sort().join(",");
      if (commandKeys !== "args,executable") {
        throw new Error(`repository configuration '${key}' item ${index + 1} needs only executable and args`);
      }
      if (typeof command.executable !== "string" || !command.executable) {
        throw new Error(`repository configuration '${key}' item ${index + 1} needs an executable`);
      }
      if (!Array.isArray(command.args) || command.args.some((argument) => typeof argument !== "string")) {
        throw new Error(`repository configuration '${key}' item ${index + 1} args must be strings`);
      }
      return { executable: command.executable, args: [...command.args] };
    });
  }
  return config;
}

export async function readRepositoryConfig(repositoryRoot, explicitPath) {
  const file = explicitPath ?? join(repositoryRoot, "docs", "agents", "sdlc.md");
  const markdown = await readFile(file, "utf8");
  return {
    file: resolve(file),
    value: validateRepositoryConfig(parseFrontmatter(markdown, file)),
  };
}

export function machineDefaults(repositoryRoot, home = homedir()) {
  const checkoutRoot = dirname(resolve(repositoryRoot));
  return {
    schemaVersion: 1,
    checkoutRoot,
    worktreeRoot: join(checkoutRoot, "worktrees"),
    worktreeManager: "git",
    executables: { git: "git", github: "gh", supacode: "supacode" },
    skillSourceRoot: join(resolve(repositoryRoot), "skills"),
    instructionSource: join(resolve(repositoryRoot), "instructions", "global.md"),
    lampwrightStateRoot: join(home, ".local", "state", "lampwright"),
    harnesses: {
      codex: {
        skillRoot: join(home, ".agents", "skills"),
        instructionFile: join(home, ".codex", "AGENTS.md"),
      },
      claude: {
        skillRoot: join(home, ".claude", "skills"),
        instructionFile: join(home, ".claude", "CLAUDE.md"),
      },
      copilot: {
        skillRoot: join(home, ".agents", "skills"),
        instructionFile: join(home, ".copilot", "copilot-instructions.md"),
      },
    },
  };
}

export function validateMachineConfig(value, repositoryRoot) {
  const defaults = machineDefaults(repositoryRoot);
  const allowed = new Set([
    "schemaVersion",
    "checkoutRoot",
    "worktreeRoot",
    "worktreeManager",
    "executables",
    "skillSourceRoot",
    "instructionSource",
    "lampwrightStateRoot",
    "harnesses",
  ]);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) throw new Error(`machine configuration has unknown key '${key}'`);
  }
  if (value.harnesses && (typeof value.harnesses !== "object" || Array.isArray(value.harnesses))) {
    throw new Error("machine configuration 'harnesses' must be an object");
  }
  const config = {
    ...defaults,
    ...value,
    executables: { ...defaults.executables, ...(value.executables ?? {}) },
    harnesses: Object.fromEntries(Object.entries(defaults.harnesses).map(([name, settings]) => [
      name,
      { ...settings, ...(value.harnesses?.[name] ?? {}) },
    ])),
  };
  if (config.schemaVersion !== 1) {
    throw new Error(`unsupported machine schemaVersion '${config.schemaVersion}'`);
  }
  for (const key of [
    "checkoutRoot",
    "worktreeRoot",
    "skillSourceRoot",
    "instructionSource",
    "lampwrightStateRoot",
  ]) {
    if (typeof config[key] !== "string" || !config[key]) {
      throw new Error(`machine configuration '${key}' must be a non-empty string`);
    }
    config[key] = resolve(config[key]);
  }
  for (const name of Object.keys(value.harnesses ?? {})) {
    if (!new Set(["codex", "claude", "copilot"]).has(name)) {
      throw new Error(`machine configuration has unknown harness '${name}'`);
    }
  }
  for (const [name, harness] of Object.entries(config.harnesses)) {
    const keys = Object.keys(harness).sort().join(",");
    if (keys !== "instructionFile,skillRoot") {
      throw new Error(`machine harness '${name}' needs only instructionFile and skillRoot`);
    }
    for (const key of ["skillRoot", "instructionFile"]) {
      if (typeof harness[key] !== "string" || !harness[key]) {
        throw new Error(`machine harness '${name}' needs a non-empty ${key}`);
      }
      harness[key] = resolve(harness[key]);
    }
  }
  if (!new Set(["supacode", "git"]).has(config.worktreeManager)) {
    throw new Error("worktreeManager must be 'supacode' or 'git'");
  }
  for (const [key, executable] of Object.entries(config.executables)) {
    if (!new Set(["git", "github", "supacode"]).has(key)) {
      throw new Error(`machine configuration has unknown executable '${key}'`);
    }
    if (typeof executable !== "string" || !executable) {
      throw new Error(`machine executable '${key}' must be a non-empty string`);
    }
  }
  return config;
}

export async function readMachineConfig(repositoryRoot, explicitPath) {
  const file = explicitPath ?? process.env.AGENT_SKILLS_CONFIG ??
    join(homedir(), ".config", "agent-skills", "config.json");
  try {
    const value = JSON.parse(await readFile(file, "utf8"));
    return { file: resolve(file), value: validateMachineConfig(value, repositoryRoot) };
  } catch (error) {
    if (error.code === "ENOENT" && !explicitPath && !process.env.AGENT_SKILLS_CONFIG) {
      return { file: null, value: machineDefaults(repositoryRoot) };
    }
    throw error;
  }
}

export function renderPattern(pattern, issue, title) {
  const slug = title
    .normalize("NFKD")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 48) || "work";
  return pattern.replaceAll("{issue}", String(issue)).replaceAll("{slug}", slug);
}

export function recordedBranch(comments, kind = "child") {
  const name = kind === "integration" ? "integration-branch" : "branch";
  const expression = new RegExp(`<!--\\s*agent-skills:sdlc-${name}:([^\\s>]+)\\s*-->`);
  for (const comment of comments ?? []) {
    const match = String(comment.body ?? comment).match(expression);
    if (match) return match[1];
  }
  return null;
}
