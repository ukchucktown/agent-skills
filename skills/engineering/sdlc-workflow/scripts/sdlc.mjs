#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { JsonSnapshotAdapter } from "./lib/file-adapters.mjs";
import { stableJson } from "./lib/json.mjs";
import { assertFreshPlan, createPlan } from "./lib/plan.mjs";
import { inspectWorkflow } from "./lib/state.mjs";

function usage() {
  return `Usage:
  sdlc.mjs inspect --repository <path> --github-snapshot <file> --worktree-snapshot <file> [--feature <number>] [--machine-config <file>] [--repository-config <file>] [--output <file>]
  sdlc.mjs plan --state <file> --request <file> [--output <file>]
  sdlc.mjs verify-plan --plan <file> --state <file> [--output <file>]
`;
}

function parseArguments(values) {
  const [command, ...rest] = values;
  if (!command || command === "--help" || command === "-h") return { command: "help", options: {} };
  const options = {};
  for (let index = 0; index < rest.length; index += 2) {
    const key = rest[index];
    const value = rest[index + 1];
    if (!key?.startsWith("--") || value === undefined) {
      throw new Error(`invalid argument near '${key ?? ""}'`);
    }
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

async function main() {
  const { command, options } = parseArguments(process.argv.slice(2));
  if (command === "help") {
    process.stdout.write(usage());
    return;
  }

  if (command === "inspect") {
    const repositoryRoot = resolve(required(options, "repository"));
    const featureNumber = options.feature ? Number.parseInt(options.feature, 10) : undefined;
    if (options.feature && !Number.isInteger(featureNumber)) {
      throw new Error("--feature must be an integer");
    }
    const state = await inspectWorkflow({
      repositoryRoot,
      repositoryConfigPath: options["repository-config"],
      machineConfigPath: options["machine-config"],
      githubAdapter: new JsonSnapshotAdapter(required(options, "github-snapshot")),
      worktreeAdapter: new JsonSnapshotAdapter(required(options, "worktree-snapshot")),
      featureNumber,
    });
    await emit(state, options.output);
    return;
  }

  if (command === "plan") {
    const state = await jsonFile(required(options, "state"));
    const request = await jsonFile(required(options, "request"));
    await emit(createPlan(state, request), options.output);
    return;
  }

  if (command === "verify-plan") {
    const plan = await jsonFile(required(options, "plan"));
    const state = await jsonFile(required(options, "state"));
    assertFreshPlan(plan, state);
    await emit({ schemaVersion: 1, planId: plan.planId, fresh: true }, options.output);
    return;
  }

  throw new Error(`unknown command '${command}'`);
}

main().catch((error) => {
  process.stderr.write(stableJson({
    schemaVersion: 1,
    error: { name: error.name, message: error.message },
  }));
  process.exitCode = 1;
});
