#!/usr/bin/env node

import { pathToFileURL } from "node:url";
import { buildStatus } from "./lib/status-model.mjs";
import {
  collectLiveWorkState,
  inferIssueNumber,
  LiveClient,
  loadFixture,
} from "./lib/runtime.mjs";

function usage() {
  return `Usage:
  gh-issue status [issue-number] [--repo OWNER/REPO] [--json]
  gh-issue status [issue-number] --fixture PATH [--json]

The current implementation is read-only. start, finish, and clean are not yet available.`;
}

export function parseArguments(argv) {
  const options = {
    command: null,
    issueNumber: null,
    repository: null,
    fixture: null,
    json: false,
    help: false,
  };

  const args = [...argv];
  while (args.length > 0) {
    const value = args.shift();
    if (value === "--json") options.json = true;
    else if (value === "--help" || value === "-h") options.help = true;
    else if (value === "--repo" || value === "--fixture") {
      const argument = args.shift();
      if (!argument) throw new Error(`${value} requires a value.`);
      if (value === "--repo") options.repository = argument;
      else options.fixture = argument;
    }
    else if (!options.command) options.command = value;
    else if (!options.issueNumber && /^#?\d+$/.test(value)) {
      options.issueNumber = Number.parseInt(value.replace(/^#/, ""), 10);
    } else {
      throw new Error(`Unexpected argument: ${value}`);
    }
  }

  return options;
}

function candidateSummary(candidate) {
  return {
    number: Number(candidate.number),
    title: candidate.title ?? "",
    url: candidate.url ?? null,
    updatedAt: candidate.updatedAt ?? null,
    parent: candidate.parent
      ? { number: Number(candidate.parent.number), title: candidate.parent.title ?? "" }
      : null,
  };
}

function formatIssue(issue) {
  return `#${issue.number} ${issue.title}`;
}

function renderIssueList(issues) {
  return issues.length > 0 ? issues.map(formatIssue).join(", ") : "None";
}

export function formatHuman(result) {
  if (result.kind === "selection_required") {
    const lines = ["Choose an open GitHub issue or provide its number:"];
    result.candidates.forEach((candidate, index) => {
      const parent = candidate.parent ? ` · parent #${candidate.parent.number}` : "";
      lines.push(`${index + 1}. ${formatIssue(candidate)}${parent}`);
    });
    if (result.candidates.length === 0) lines.push("No authored or assigned open issues found.");
    return lines.join("\n");
  }

  if (result.kind === "unavailable") return result.message;

  const lines = [
    `${formatIssue(result.issue)} · ${result.classification} · ${result.workflowState}`,
    `Repository: ${result.repository} · stable branch: ${result.stableBranch}`,
  ];

  if (result.ancestors.length > 0) {
    lines.push(`Parents: ${result.ancestors.map(formatIssue).join(" → ")}`);
  }

  const worktrees = result.work.worktrees;
  const branches = result.work.branches;
  lines.push(
    `Worktrees: ${worktrees.length > 0 ? worktrees.map((item) => `${item.path}${item.dirty ? " (dirty)" : ""}`).join(", ") : "None"}`,
  );
  lines.push(
    `Branches: ${branches.length > 0 ? branches.map((item) => item.name ?? item).join(", ") : "None"}`,
  );

  if (result.pullRequests.length > 0) {
    for (const pr of result.pullRequests) {
      const checks = pr.checks.length
        ? pr.checks.map((check) => `${check.name}: ${check.conclusion ?? check.status ?? "unknown"}`).join(", ")
        : "no checks";
      lines.push(`PR #${pr.number}: ${pr.state} · ${pr.head} → ${pr.base} · ${checks}`);
    }
  } else {
    lines.push("Pull requests: None");
  }

  lines.push(`Blockers: ${renderIssueList(result.blockers)}`);

  if (result.classification === "compound") {
    lines.push("Children:");
    for (const state of ["in_progress", "ready", "blocked", "completed"]) {
      lines.push(`  ${state}: ${renderIssueList(result.children[state])}`);
    }
  }

  for (const conflict of result.conflicts) {
    lines.push(`Conflict: ${conflict.kind} on issue #${conflict.issue.number}`);
  }
  for (const warning of result.warnings) lines.push(`Warning: ${warning}`);

  if (result.recommendation) {
    lines.push(`Recommended: ${formatIssue(result.recommendation.issue)}`);
    lines.push(`Reason: ${result.recommendation.reason}`);
  }
  lines.push(`Next: ${result.nextAction}`);
  return lines.join("\n");
}

export async function runCommand(options) {
  if (options.help || !options.command) return { kind: "help", text: usage() };
  if (!["status", "start", "finish", "clean"].includes(options.command)) {
    throw new Error(`Unknown command: ${options.command}`);
  }
  if (options.command !== "status") {
    return {
      kind: "unavailable",
      command: options.command,
      message: `${options.command} is intentionally unavailable in the read-only foundation.`,
    };
  }

  const isFixture = Boolean(options.fixture);
  const runtime = isFixture
    ? loadFixture(options.fixture)
    : (() => {
        const client = LiveClient.create({ repository: options.repository });
        return {
          client,
          workState: collectLiveWorkState(client, { includePullRequests: false }),
        };
      })();

  const issueNumber = options.issueNumber ?? inferIssueNumber(runtime.workState);
  if (!issueNumber) {
    return {
      kind: "selection_required",
      repository: runtime.client.repository,
      candidates: (await runtime.client.listCandidates()).map(candidateSummary),
    };
  }

  if (!isFixture) runtime.workState.pullRequests = runtime.client.listPullRequests();

  return buildStatus({
    client: runtime.client,
    workState: runtime.workState,
    issueNumber,
  });
}

async function main() {
  let options;
  try {
    options = parseArguments(process.argv.slice(2));
    const result = await runCommand(options);
    if (result.kind === "help") {
      process.stdout.write(`${result.text}\n`);
    } else if (options.json) {
      process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    } else {
      process.stdout.write(`${formatHuman(result)}\n`);
    }
    if (result.kind === "unavailable") process.exitCode = 2;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (options?.json) {
      process.stdout.write(`${JSON.stringify({ kind: "error", message }, null, 2)}\n`);
    } else {
      process.stderr.write(`gh-issue: ${message}\n`);
    }
    process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main();
