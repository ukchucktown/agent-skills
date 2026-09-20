#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import { readRepositoryConfig } from "../../sdlc-workflow/scripts/lib/config.mjs";
import { stableJson } from "../../sdlc-workflow/scripts/lib/json.mjs";
import {
  applyFeatureMergePlan,
  assertFeatureCandidate,
  createFeatureMergePlan,
  runFeatureValidation,
  submitFeature,
} from "./lib/feature-core.mjs";
import {
  FeatureGitAdapter,
  FeatureGitHubAdapter,
  GitCleanupAdapter,
} from "./lib/feature-adapters.mjs";
import { FeatureInspector } from "./lib/feature-inspector.mjs";

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

async function current(options, featureOverride) {
  const repositoryRoot = resolve(required(options, "repository"));
  const feature = featureOverride ?? Number.parseInt(required(options, "feature"), 10);
  if (!Number.isInteger(feature)) throw new Error("--feature must be an integer");
  const repository = await readRepositoryConfig(repositoryRoot);
  const inspector = new FeatureInspector(repositoryRoot, repository.value);
  const snapshot = await inspector.inspect(feature);
  assertFeatureCandidate(snapshot, repository.value);
  const validation = runFeatureValidation(snapshot, repository.value, execFileSync);
  return { repositoryRoot, repository: repository.value, inspector, snapshot, validation };
}

async function main() {
  const { command, options } = parseArguments(process.argv.slice(2));
  if (command === "help") {
    process.stdout.write(`Usage:\n  finish-feature.mjs prepare --repository <stable-checkout> --feature <number> [--output <file>]\n  finish-feature.mjs submit --repository <stable-checkout> --feature <number> --specification-review <file> [--output <file>]\n  finish-feature.mjs merge-plan --repository <stable-checkout> --feature <number> --specification-review <file> [--output <file>]\n  finish-feature.mjs merge --repository <stable-checkout> --plan <file> --approved <planId> [--output <file>]\n`);
    return;
  }
  if (command === "prepare") {
    const value = await current(options);
    await emit({
      schemaVersion: 1,
      feature: value.snapshot.parent.number,
      integrationBranch: value.snapshot.integrationBranch,
      stableBranch: value.snapshot.stableBranch,
      candidateCommit: value.snapshot.candidateCommit,
      validation: value.validation,
      specificationReview: {
        schemaVersion: 1,
        axis: "specification",
        candidateCommit: value.snapshot.candidateCommit,
        verdict: "fail",
        summary: "Pending integrated specification review. Replace this summary and verdict after review.",
      },
    }, options.output);
    return;
  }
  if (command === "submit") {
    const value = await current(options);
    await emit(await submitFeature({
      snapshot: value.snapshot,
      config: value.repository,
      validation: value.validation,
      specificationReview: await jsonFile(required(options, "specification-review")),
      git: new FeatureGitAdapter(value.repositoryRoot),
      github: new FeatureGitHubAdapter(value.repositoryRoot),
    }), options.output);
    return;
  }
  if (command === "merge-plan") {
    const value = await current(options);
    await emit(createFeatureMergePlan(value.snapshot, value.repository, {
      validation: value.validation,
      specificationReview: await jsonFile(required(options, "specification-review")),
    }), options.output);
    return;
  }
  if (command === "merge") {
    const plan = await jsonFile(required(options, "plan"));
    const value = await current(options, plan.feature);
    await emit(await applyFeatureMergePlan({
      plan,
      approved: required(options, "approved"),
      currentSnapshot: value.snapshot,
      config: value.repository,
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
