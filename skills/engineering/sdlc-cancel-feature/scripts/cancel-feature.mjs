#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import { readRepositoryConfig } from "../../sdlc-workflow/scripts/lib/config.mjs";
import { stableJson } from "../../sdlc-workflow/scripts/lib/json.mjs";
import {
  applyCancellationPlan,
  createCancellationPlan,
} from "../../sdlc-finish-feature/scripts/lib/feature-core.mjs";
import {
  FeatureGitHubAdapter,
  GitCleanupAdapter,
} from "../../sdlc-finish-feature/scripts/lib/feature-adapters.mjs";
import { FeatureInspector } from "../../sdlc-finish-feature/scripts/lib/feature-inspector.mjs";

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

async function inspect(options, featureOverride) {
  const repositoryRoot = resolve(required(options, "repository"));
  const feature = featureOverride ?? Number.parseInt(required(options, "feature"), 10);
  if (!Number.isInteger(feature)) throw new Error("--feature must be an integer");
  const repository = await readRepositoryConfig(repositoryRoot);
  const snapshot = await new FeatureInspector(
    repositoryRoot,
    repository.value,
  ).inspect(feature);
  if (snapshot.invocationBranch !== repository.value.stableBranch) {
    throw new Error(`run feature cancellation from the stable checkout '${repository.value.stableBranch}'`);
  }
  if (!snapshot.parent.labels.includes(repository.value.featureLabel)) {
    throw new Error(`issue #${feature} is not labeled '${repository.value.featureLabel}'`);
  }
  return { repositoryRoot, repository: repository.value, snapshot };
}

async function main() {
  const { command, options } = parseArguments(process.argv.slice(2));
  if (command === "help") {
    process.stdout.write(`Usage:\n  cancel-feature.mjs plan --repository <stable-checkout> --feature <number> [--output <file>]\n  cancel-feature.mjs apply --repository <stable-checkout> --plan <file> --approved <planId> [--output <file>]\n`);
    return;
  }
  if (command === "plan") {
    const value = await inspect(options);
    await emit(createCancellationPlan(value.snapshot), options.output);
    return;
  }
  if (command === "apply") {
    const plan = await jsonFile(required(options, "plan"));
    const value = await inspect(options, plan.feature);
    await emit(await applyCancellationPlan({
      plan,
      approved: required(options, "approved"),
      currentSnapshot: value.snapshot,
      github: new FeatureGitHubAdapter(value.repositoryRoot),
      cleanup: new GitCleanupAdapter(value.repositoryRoot),
    }), options.output);
    return;
  }
  throw new Error(`unknown command '${command}'`);
}

main().catch((error) => {
  process.stderr.write(stableJson({ schemaVersion: 1, error: { name: error.name, message: error.message } }));
  process.exitCode = 1;
});
