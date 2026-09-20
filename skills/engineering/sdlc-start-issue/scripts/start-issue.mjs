#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import {
  readMachineConfig,
  readRepositoryConfig,
} from "../../sdlc-workflow/scripts/lib/config.mjs";
import { stableJson } from "../../sdlc-workflow/scripts/lib/json.mjs";
import {
  GitHubStartAdapter,
  GitWorktreeAdapter,
  SupacodeWorktreeAdapter,
} from "./lib/adapters.mjs";
import { StartInspector } from "./lib/inspector.mjs";
import { applyStartPlan, createStartPlan } from "./lib/starter.mjs";

function parseArguments(values) {
  const [command, ...rest] = values;
  if (!command || command === "--help" || command === "-h") return { command: "help", options: {} };
  const options = {};
  for (let index = 0; index < rest.length; index += 2) {
    const key = rest[index];
    const value = rest[index + 1];
    if (!key?.startsWith("--") || value === undefined) throw new Error(`invalid argument near '${key ?? ""}'`);
    options[key.slice(2)] = value;
  }
  return { command, options };
}

function required(options, key) {
  if (!options[key]) throw new Error(`--${key} is required`);
  return options[key];
}

async function jsonFile(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

async function emit(value, output) {
  const rendered = stableJson(value);
  if (output) await writeFile(output, rendered, "utf8");
  else process.stdout.write(rendered);
}

async function context(repositoryRoot, issueNumber, machineConfigPath) {
  const [repository, machine] = await Promise.all([
    readRepositoryConfig(repositoryRoot),
    readMachineConfig(repositoryRoot, machineConfigPath),
  ]);
  const inspector = new StartInspector(repositoryRoot, repository.value, machine.value);
  return { repository: repository.value, machine: machine.value, inspector, issueNumber };
}

async function planFrom(options) {
  const repositoryRoot = resolve(required(options, "repository"));
  const issueNumber = Number.parseInt(required(options, "issue"), 10);
  if (!Number.isInteger(issueNumber)) throw new Error("--issue must be an integer");
  const current = await context(repositoryRoot, issueNumber, options["machine-config"]);
  const snapshot = await current.inspector.inspect(issueNumber);
  return {
    plan: createStartPlan({
      snapshot,
      repositoryConfig: current.repository,
      machineConfig: current.machine,
      repositoryRoot,
      overrideAssignment: options["override-assignment"],
    }),
    current,
  };
}

async function apply(plan, machineConfigPath) {
  const current = await context(plan.repositoryRoot, plan.issue, machineConfigPath);
  const github = new GitHubStartAdapter(plan.repositoryRoot, plan.repository);
  const manager = plan.worktree.manager;
  const worktree = manager === "supacode"
    ? new SupacodeWorktreeAdapter(plan.repositoryRoot)
    : new GitWorktreeAdapter(plan.repositoryRoot);
  return applyStartPlan({
    plan,
    inspect: () => current.inspector.inspect(plan.issue),
    adapters: { github, worktree },
  });
}

async function main() {
  const { command, options } = parseArguments(process.argv.slice(2));
  if (command === "help") {
    process.stdout.write(`Usage:\n  start-issue.mjs start --repository <path> --issue <number> [--override-assignment <reason>] [--machine-config <file>] [--output <file>]\n  start-issue.mjs plan --repository <path> --issue <number> [--override-assignment <reason>] [--machine-config <file>] [--output <file>]\n  start-issue.mjs apply --plan <file> [--machine-config <file>] [--output <file>]\n`);
    return;
  }
  if (command === "plan") {
    const { plan } = await planFrom(options);
    await emit(plan, options.output);
    return;
  }
  if (command === "apply") {
    await emit(
      await apply(await jsonFile(required(options, "plan")), options["machine-config"]),
      options.output,
    );
    return;
  }
  if (command === "start") {
    const { plan } = await planFrom(options);
    await emit(await apply(plan, options["machine-config"]), options.output);
    return;
  }
  throw new Error(`unknown command '${command}'`);
}

main().catch((error) => {
  process.stderr.write(stableJson({ schemaVersion: 1, error: { name: error.name, message: error.message } }));
  process.exitCode = 1;
});
