#!/usr/bin/env node

import { existsSync, mkdirSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { performance } from "node:perf_hooks";

const START_QUERY = fileURLToPath(
  new URL("../references/start.graphql", import.meta.url),
);

export function parseArguments(argv) {
  const options = {
    repository: ".",
    manager: undefined,
    dryRun: false,
    json: false,
    fetch: true,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--dry-run") options.dryRun = true;
    else if (argument === "--json") options.json = true;
    else if (argument === "--no-fetch") options.fetch = false;
    else if (argument === "--help" || argument === "-h") options.help = true;
    else if (argument.startsWith("--")) {
      const key = argument.slice(2);
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        throw new Error(`${argument} requires a value`);
      }
      index += 1;
      if (key === "issue") options.issue = Number(value);
      else if (key === "repository") options.repository = value;
      else if (key === "manager") options.manager = value;
      else if (key === "worktree-root") options.worktreeRoot = value;
      else if (key === "config") options.config = value;
      else throw new Error(`Unknown option: ${argument}`);
    } else {
      throw new Error(`Unexpected argument: ${argument}`);
    }
  }

  if (!options.help && (!Number.isInteger(options.issue) || options.issue < 1)) {
    throw new Error("--issue must be a positive integer");
  }
  if (options.manager && !["auto", "supacode", "git"].includes(options.manager)) {
    throw new Error("--manager must be auto, supacode, or git");
  }
  return options;
}

export function parseGitHubRemote(remote) {
  const match = remote.trim().match(
    /(?:github\.com[/:])([^/]+)\/([^/]+?)(?:\.git)?$/i,
  );
  if (!match) throw new Error(`Origin is not a GitHub repository: ${remote}`);
  return { owner: match[1], name: match[2] };
}

export function slugify(title) {
  const slug = title
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 48)
    .replace(/-$/g, "");
  return slug || "issue";
}

export function buildStartPlan({
  issue,
  defaultBranch,
  repositoryName,
  worktreeRoot,
  integrationBranchTemplate = "integration/issue-{number}-{slug}",
  taskBranchTemplate = "feat/issue-{number}-{slug}",
  worktreeTemplate = "issue-{number}-{slug}",
}) {
  if (!issue) throw new Error("GitHub did not return the requested issue");
  if (!defaultBranch) throw new Error("GitHub did not return the default branch");
  if (issue.state !== "OPEN") throw new Error(`Issue #${issue.number} is not open`);

  const ancestors = [];
  let parent = issue.parent;
  while (parent) {
    if (!parent.title || !parent.state) {
      throw new Error("Issue hierarchy exceeds the supported depth of seven parents");
    }
    if (parent.state !== "OPEN") {
      throw new Error(`Parent issue #${parent.number} is not open`);
    }
    ancestors.unshift(parent);
    parent = parent.parent;
  }

  const render = (template, item) =>
    template
      .replaceAll("{number}", String(item.number))
      .replaceAll("{slug}", slugify(item.title));

  const items = ancestors.map((item) => ({ item, kind: "integration" }));
  const classification = issue.subIssues.totalCount > 0 ? "compound" : "standalone";
  items.push({
    item: issue,
    kind: classification === "compound" ? "integration" : "task",
  });

  let baseBranch = defaultBranch;
  const steps = items.map(({ item, kind }) => {
    const branch = render(
      kind === "integration" ? integrationBranchTemplate : taskBranchTemplate,
      item,
    );
    const worktreeName = render(worktreeTemplate, item);
    const step = {
      issue: item.number,
      title: item.title,
      kind,
      branch,
      baseBranch,
      worktreeName,
      destination: path.join(worktreeRoot, repositoryName, worktreeName),
    };
    if (kind === "integration") baseBranch = branch;
    return step;
  });

  return { classification, steps };
}

export function parseWorktrees(output) {
  const worktrees = [];
  let current;
  for (const line of output.split("\n")) {
    if (line.startsWith("worktree ")) {
      current = { path: line.slice(9) };
      worktrees.push(current);
    } else if (current && line.startsWith("branch refs/heads/")) {
      current.branch = line.slice("branch refs/heads/".length);
    }
  }
  return worktrees;
}

function systemRun(command, args, { cwd, allowFailure = false } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.error) {
    if (allowFailure) return { ok: false, stdout: "", stderr: result.error.message };
    throw result.error;
  }
  if (result.status !== 0 && !allowFailure) {
    const detail = result.stderr.trim() || result.stdout.trim();
    throw new Error(`${command} failed${detail ? `: ${detail}` : ""}`);
  }
  return {
    ok: result.status === 0,
    stdout: result.stdout.trim(),
    stderr: result.stderr.trim(),
  };
}

function git(run, repository, args, options = {}) {
  return run("git", ["-C", repository, ...args], options).stdout;
}

function loadConfig(configPath) {
  if (!existsSync(configPath)) return {};
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(configPath, "utf8"));
  } catch (error) {
    throw new Error(`Cannot read ${configPath}: ${error.message}`);
  }
  const config = parsed["gh-issue"] ?? {};
  if (!config || Array.isArray(config) || typeof config !== "object") {
    throw new Error(`${configPath} must contain a gh-issue object`);
  }
  return config;
}

function normalizePath(value) {
  const trimmed = value.replace(/[\\/]$/, "");
  try {
    return realpathSync(trimmed);
  } catch {
    return path.resolve(trimmed);
  }
}

function resolveSupacode(run, primaryRepository, requestedManager) {
  if (requestedManager === "git") return { manager: "git" };
  const result = run("supacode", ["repo", "list"], { allowFailure: true });
  if (result.ok) {
    const repositoryId = result.stdout
      .split("\n")
      .filter(Boolean)
      .find((candidate) => {
        try {
          return normalizePath(decodeURIComponent(candidate)) === primaryRepository;
        } catch {
          return false;
        }
      });
    if (repositoryId) return { manager: "supacode", repositoryId };
  }
  if (requestedManager === "supacode") {
    throw new Error("The primary repository is not available in Supacode");
  }
  return { manager: "git" };
}

function inspectActions(run, primaryRepository, steps) {
  const worktrees = parseWorktrees(
    git(run, primaryRepository, ["worktree", "list", "--porcelain"]),
  );
  const refs = new Set(
    git(run, primaryRepository, [
      "for-each-ref",
      "--format=%(refname)",
      "refs/heads",
      "refs/remotes/origin",
    ])
      .split("\n")
      .filter(Boolean),
  );

  return steps.map((step) => {
    const existingWorktree = worktrees.find((item) => item.branch === step.branch);
    if (existingWorktree) {
      return { ...step, action: "reuse", destination: existingWorktree.path };
    }
    if (existsSync(step.destination)) {
      throw new Error(`Destination already exists: ${step.destination}`);
    }
    if (refs.has(`refs/heads/${step.branch}`)) {
      return { ...step, action: "add-existing" };
    }
    if (refs.has(`refs/remotes/origin/${step.branch}`)) {
      return { ...step, action: "track-remote" };
    }
    return { ...step, action: "create" };
  });
}

function assertReusableWorktreesClean(run, actions) {
  if (!actions.some((step) => step.action !== "reuse")) return;
  for (const step of actions.filter((item) => item.action === "reuse")) {
    const changes = git(run, step.destination, ["status", "--porcelain"]);
    if (changes) {
      throw new Error(
        `Existing worktree for ${step.branch} has uncommitted changes: ${step.destination}`,
      );
    }
  }
}

function validateBranches(run, primaryRepository, actions) {
  for (const step of actions) {
    run("git", ["check-ref-format", "--branch", step.branch]);
  }
  const available = new Set(
    git(run, primaryRepository, [
      "for-each-ref",
      "--format=%(refname:short)",
      "refs/heads",
      "refs/remotes/origin",
    ])
      .split("\n")
      .filter(Boolean),
  );
  for (let index = 0; index < actions.length; index += 1) {
    const step = actions[index];
    if (step.action === "create" && index === 0) {
      const baseAvailable =
        available.has(step.baseBranch) || available.has(`origin/${step.baseBranch}`);
      if (!baseAvailable) throw new Error(`Base branch is unavailable: ${step.baseBranch}`);
    }
  }
}

function addWorktree(run, context, step) {
  const base =
    step.action === "track-remote"
      ? `origin/${step.branch}`
      : context.localBranches.has(step.baseBranch)
        ? step.baseBranch
        : `origin/${step.baseBranch}`;

  if (context.manager === "supacode") {
    const args = [
      "repo",
      "worktree-new",
      "-r",
      context.repositoryId,
      "--branch",
      step.branch,
    ];
    if (step.action === "create") args.push("--base", base);
    if (step.action === "track-remote") {
      args.push("--base", base, "--upstream", base);
    }
    args.push(
      "--location",
      context.repositoryWorktreeRoot,
      "--name",
      step.worktreeName,
      "--background",
    );
    run("supacode", args);
  } else {
    const args = ["worktree", "add"];
    if (step.action === "create") args.push("-b", step.branch, step.destination, base);
    else if (step.action === "track-remote") {
      args.push("-b", step.branch, "--track", step.destination, base);
    } else args.push(step.destination, step.branch);
    git(run, context.primaryRepository, args);
  }

  const actualBranch = git(run, step.destination, ["branch", "--show-current"]);
  if (actualBranch !== step.branch) {
    throw new Error(`Expected ${step.branch} at ${step.destination}, found ${actualBranch}`);
  }
  context.localBranches.add(step.branch);
}

export function startIssue(options, dependencies = {}) {
  const run = dependencies.run ?? systemRun;
  const startedAt = performance.now();
  const repositoryInput = path.resolve(options.repository);
  const currentWorktree = normalizePath(
    git(run, repositoryInput, ["rev-parse", "--show-toplevel"]),
  );
  const commonDirectory = normalizePath(
    git(run, currentWorktree, [
      "rev-parse",
      "--path-format=absolute",
      "--git-common-dir",
    ]),
  );
  const primaryRepository = path.dirname(commonDirectory);
  const remote = git(run, primaryRepository, ["remote", "get-url", "origin"]);
  const { owner, name } = parseGitHubRemote(remote);

  const configPath = path.resolve(
    options.config ??
      process.env.AGENT_SKILLS_CONFIG ??
      path.join(homedir(), ".config", "agent-skills", "config.json"),
  );
  const config = loadConfig(configPath);
  const managerPreference = options.manager ?? config.worktreeManager ?? "auto";
  if (!["auto", "supacode", "git"].includes(managerPreference)) {
    throw new Error("Configured worktreeManager must be auto, supacode, or git");
  }
  const worktreeRoot = path.resolve(
    options.worktreeRoot ??
      config.worktreeRoot ??
      path.join(path.dirname(primaryRepository), "worktrees"),
  );

  const githubStartedAt = performance.now();
  const github = run("gh", [
    "api",
    "graphql",
    "-F",
    `owner=${owner}`,
    "-F",
    `name=${name}`,
    "-F",
    `number=${options.issue}`,
    "-F",
    `query=@${START_QUERY}`,
  ]);
  let response;
  try {
    response = JSON.parse(github.stdout);
  } catch {
    throw new Error("GitHub returned invalid JSON");
  }
  const repository = response.data?.repository;
  if (!repository) throw new Error(`GitHub repository not found: ${owner}/${name}`);
  const githubMs = performance.now() - githubStartedAt;

  if (options.fetch) {
    git(run, primaryRepository, ["fetch", "--quiet", "--prune", "origin"]);
  }

  const plan = buildStartPlan({
    issue: repository.issue,
    defaultBranch: repository.defaultBranchRef?.name,
    repositoryName: name,
    worktreeRoot,
    integrationBranchTemplate: config.integrationBranchTemplate,
    taskBranchTemplate: config.taskBranchTemplate,
    worktreeTemplate: config.worktreeTemplate,
  });
  const actions = inspectActions(run, primaryRepository, plan.steps);
  validateBranches(run, primaryRepository, actions);
  assertReusableWorktreesClean(run, actions);
  const manager = resolveSupacode(run, primaryRepository, managerPreference);

  if (!options.dryRun) {
    const repositoryWorktreeRoot = path.join(worktreeRoot, name);
    mkdirSync(repositoryWorktreeRoot, { recursive: true });
    const localBranches = new Set(
      git(run, primaryRepository, [
        "for-each-ref",
        "--format=%(refname:short)",
        "refs/heads",
      ])
        .split("\n")
        .filter(Boolean),
    );
    const context = {
      ...manager,
      primaryRepository,
      repositoryWorktreeRoot,
      localBranches,
    };
    for (const step of actions) {
      if (step.action !== "reuse") addWorktree(run, context, step);
    }

    const integrationBranches = actions
      .filter((step) => {
        if (step.kind !== "integration") return false;
        return !git(
          run,
          primaryRepository,
          ["show-ref", "--verify", `refs/remotes/origin/${step.branch}`],
          { allowFailure: true },
        );
      })
      .map((step) => step.branch);
    if (integrationBranches.length > 0) {
      git(run, primaryRepository, [
        "push",
        "--quiet",
        "--set-upstream",
        "origin",
        ...integrationBranches,
      ]);
    }
  }

  return {
    repository: repository.nameWithOwner,
    issue: {
      number: repository.issue.number,
      title: repository.issue.title,
      url: repository.issue.url,
    },
    classification: plan.classification,
    manager: manager.manager,
    dryRun: options.dryRun,
    actions,
    timing: {
      githubMs: Math.round(githubMs),
      totalMs: Math.round(performance.now() - startedAt),
    },
  };
}

function render(result) {
  const verb = result.dryRun ? "Plan" : "Started";
  const lines = [
    `${verb} #${result.issue.number}: ${result.issue.title}`,
    `Repository: ${result.repository}`,
    `Type: ${result.classification}`,
    `Manager: ${result.manager}`,
  ];
  for (const action of result.actions) {
    lines.push(
      `${action.kind === "integration" ? "Integration" : "Task"}: ${action.branch}`,
      `  ${action.action === "reuse" ? "Reuse" : "Create"}: ${action.destination}`,
      `  Base: ${action.baseBranch}`,
    );
  }
  lines.push(
    `Elapsed: ${(result.timing.totalMs / 1000).toFixed(2)}s ` +
      `(GitHub ${(result.timing.githubMs / 1000).toFixed(2)}s)`,
  );
  if (!result.dryRun) lines.push(`Next: implement issue #${result.issue.number}.`);
  return lines.join("\n");
}

function usage() {
  return `Usage: node start.mjs --issue NUMBER [options]

Options:
  --repository PATH       Checkout or linked worktree (default: current directory)
  --manager MODE          auto, supacode, or git
  --worktree-root PATH    Parent directory that contains repository worktrees
  --config PATH           Configuration file (default: ~/.config/agent-skills/config.json)
  --dry-run               Resolve and display the plan without mutation
  --json                  Print JSON
  --no-fetch              Use current remote-tracking refs
  --help                  Show this help`;
}

const isMain =
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;

if (isMain) {
  try {
    const options = parseArguments(process.argv.slice(2));
    if (options.help) console.log(usage());
    else {
      const result = startIssue(options);
      console.log(options.json ? JSON.stringify(result, null, 2) : render(result));
    }
  } catch (error) {
    console.error(`gh-issue start: ${error.message}`);
    process.exitCode = 1;
  }
}
