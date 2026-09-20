#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { stableJson } from "../../sdlc-workflow/scripts/lib/json.mjs";
import {
  applySetupPlan,
  createSetupPlan,
  NodeFileAdapter,
  snapshotFiles,
} from "./lib/setup-core.mjs";

const skillRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const templateFiles = [
  ".github/workflows/sdlc-contract.yml",
  ".github/workflows/sdlc-close-child.yml",
  ".github/scripts/sdlc-contract-lib.mjs",
  ".github/scripts/sdlc-pr-contract.mjs",
  ".github/scripts/sdlc-close-child.mjs",
];

function usage() {
  return `Usage:
  setup.mjs plan --repository <path> [--settings <file>] [--output <file>]
  setup.mjs apply --plan <file> [--output <file>]
`;
}

function argumentsFor(values) {
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

async function templates() {
  return Object.fromEntries(await Promise.all(templateFiles.map(async (file) => [
    file,
    await readFile(join(skillRoot, "templates", file), "utf8"),
  ])));
}

class GhLabelAdapter {
  constructor(repositoryRoot) {
    this.repositoryRoot = repositoryRoot;
    this.repository = null;
  }

  gh(argumentsList) {
    return execFileSync("gh", argumentsList, {
      cwd: this.repositoryRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
  }

  repositoryName() {
    if (!this.repository) {
      const value = JSON.parse(this.gh(["repo", "view", "--json", "nameWithOwner"]));
      this.repository = value.nameWithOwner;
    }
    return this.repository;
  }

  async snapshot() {
    const repository = this.repositoryName();
    const labels = JSON.parse(this.gh([
      "label", "list", "--repo", repository, "--limit", "1000",
      "--json", "name,color,description",
    ]));
    return { repository, labels };
  }

  async ensureLabel(label) {
    this.gh([
      "label", "create", label.name,
      "--repo", this.repositoryName(),
      "--color", label.color,
      "--description", label.description,
      "--force",
    ]);
  }
}

async function main() {
  const { command, options } = argumentsFor(process.argv.slice(2));
  if (command === "help") {
    process.stdout.write(usage());
    return;
  }

  if (command === "plan") {
    const repositoryRoot = resolve(required(options, "repository"));
    const fileAdapter = new NodeFileAdapter(repositoryRoot);
    const githubAdapter = new GhLabelAdapter(repositoryRoot);
    const [files, labels, templateValues, settings, mattLocations] = await Promise.all([
      snapshotFiles(fileAdapter),
      githubAdapter.snapshot(),
      templates(),
      options.settings ? jsonFile(options.settings) : {},
      fileAdapter.detectMattConfiguration(),
    ]);
    await emit(createSetupPlan({
      repositoryRoot,
      settings,
      files,
      labels,
      templates: templateValues,
      mattLocations,
    }), options.output);
    return;
  }

  if (command === "apply") {
    const plan = await jsonFile(required(options, "plan"));
    const fileAdapter = new NodeFileAdapter(plan.repositoryRoot);
    const githubAdapter = new GhLabelAdapter(plan.repositoryRoot);
    await emit(await applySetupPlan({ plan, fileAdapter, githubAdapter }), options.output);
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
