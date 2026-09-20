#!/usr/bin/env node

import { access, readdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

import {
  readMachineConfig,
  readRepositoryConfig,
} from "../../sdlc-workflow/scripts/lib/config.mjs";
import { stableJson } from "../../sdlc-workflow/scripts/lib/json.mjs";
import { deriveWorkflowState } from "../../sdlc-workflow/scripts/lib/state.mjs";
import { GitWorktreeSnapshotAdapter, LiveGitHubAdapter } from "./lib/live-adapters.mjs";

function parseArguments(values) {
  const options = { all: false, json: false };
  for (let index = 0; index < values.length; index += 1) {
    const key = values[index];
    if (key === "--all" || key === "--json") {
      options[key.slice(2)] = true;
      continue;
    }
    if (!key.startsWith("--") || values[index + 1] === undefined) {
      throw new Error(`invalid argument near '${key}'`);
    }
    options[key.slice(2)] = values[index + 1];
    index += 1;
  }
  return options;
}

async function exists(file) {
  try {
    await access(file);
    return true;
  } catch {
    return false;
  }
}

export async function repositoryRoots(options) {
  if (!options.all) return [resolve(options.repository ?? ".")];
  const machine = await readMachineConfig(
    resolve(options.repository ?? "."),
    options["machine-config"],
  );
  const entries = await readdir(machine.value.checkoutRoot, { withFileTypes: true });
  const configured = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    if (!entry.isDirectory()) continue;
    const root = join(machine.value.checkoutRoot, entry.name);
    if (await exists(join(root, "docs", "agents", "sdlc.md"))) configured.push(root);
  }
  return configured;
}

function nextCommand(state) {
  switch (state.nextAction.kind) {
    case "start-issue":
    case "continue-issue":
      return `/sdlc-start-issue ${state.nextAction.issue}`;
    case "finish-issue":
      return `/sdlc-finish-issue ${state.nextAction.issue}`;
    case "finish-feature":
      return `/sdlc-finish-feature ${state.feature.number}`;
    default:
      return null;
  }
}

export function statusView(state) {
  return {
    schemaVersion: 1,
    repository: state.repository.slug,
    feature: state.feature,
    groups: {
      blocked: state.children.filter((child) => child.status === "blocked"),
      ready: state.children.filter((child) => child.status === "ready"),
      active: state.children.filter((child) =>
        child.status === "in_progress" || child.status === "review"),
      complete: state.children.filter((child) =>
        child.status === "complete" || child.status === "cancelled"),
    },
    warnings: state.warnings,
    nextAction: state.nextAction,
    nextCommand: nextCommand(state),
  };
}

function issueList(values, details) {
  if (values.length === 0) return "none";
  return values.map((issue) => details(issue)).join(", ");
}

function render(view) {
  const lines = [
    `${view.repository} feature #${view.feature.number}: ${view.feature.status}`,
    `Integration: ${view.feature.integrationBranch}`,
    `Blocked: ${issueList(view.groups.blocked, (issue) =>
      `#${issue.number} (by ${issue.openBlockers.map((number) => `#${number}`).join(", ")})`)}`,
    `Ready: ${issueList(view.groups.ready, (issue) => `#${issue.number}`)}`,
    `Active: ${issueList(view.groups.active, (issue) => `#${issue.number} (${issue.status})`)}`,
    `Complete: ${issueList(view.groups.complete, (issue) => `#${issue.number}`)}`,
  ];
  for (const warning of view.warnings) lines.push(`Warning: ${warning}`);
  lines.push(view.nextCommand
    ? `Next: ${view.nextCommand}`
    : `Next: no valid command; ${view.nextAction.summary}`);
  return `${lines.join("\n")}\n`;
}

async function repositoryStatus(repositoryRoot, options) {
  const [repository, machine] = await Promise.all([
    readRepositoryConfig(repositoryRoot),
    readMachineConfig(repositoryRoot, options["machine-config"]),
  ]);
  const github = new LiveGitHubAdapter(repositoryRoot, repository.value);
  const worktrees = await new GitWorktreeSnapshotAdapter(repositoryRoot).snapshot();
  const explicit = options.feature ? Number.parseInt(options.feature, 10) : undefined;
  if (options.feature && !Number.isInteger(explicit)) throw new Error("--feature must be an integer");
  const features = await github.featureNumbers(explicit);
  const views = [];
  for (const featureNumber of features) {
    const snapshot = await github.snapshot(featureNumber);
    views.push(statusView(deriveWorkflowState({
      repositoryRoot,
      repositoryConfig: repository.value,
      machineConfig: machine.value,
      githubSnapshot: snapshot,
      worktreeSnapshot: worktrees,
      featureNumber,
    })));
  }
  return views;
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const roots = await repositoryRoots(options);
  const views = [];
  for (const root of roots) views.push(...await repositoryStatus(root, options));
  if (options.json) process.stdout.write(stableJson({ schemaVersion: 1, repositories: views }));
  else if (views.length === 0) process.stdout.write("No open coordinated features found.\n");
  else process.stdout.write(views.map(render).join("\n"));
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => {
    process.stderr.write(stableJson({ schemaVersion: 1, error: { name: error.name, message: error.message } }));
    process.exitCode = 1;
  });
}
