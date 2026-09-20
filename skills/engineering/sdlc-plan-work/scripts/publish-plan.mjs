#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import { readRepositoryConfig } from "../../sdlc-workflow/scripts/lib/config.mjs";
import { stableJson } from "../../sdlc-workflow/scripts/lib/json.mjs";
import { applyPublishPlan, createPublishPlan } from "./lib/publisher.mjs";

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

class GhIssueAdapter {
  gh(argumentsList) {
    return execFileSync("gh", argumentsList, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
  }

  async findByMarker(repository, marker) {
    const issues = JSON.parse(this.gh([
      "issue", "list", "--repo", repository, "--state", "all", "--limit", "1000",
      "--json", "number,body,title,url",
    ]));
    const match = issues.find((issue) => issue.body?.includes(marker));
    if (!match) return null;
    const detail = JSON.parse(this.gh(["api", `repos/${repository}/issues/${match.number}`]));
    return { number: match.number, id: detail.id, title: match.title, url: match.url };
  }

  async createIssue(repository, issue) {
    const argumentsList = [
      "api", "--method", "POST", `repos/${repository}/issues`,
      "-f", `title=${issue.title}`,
      "-f", `body=${issue.body}`,
    ];
    for (const label of issue.labels) argumentsList.push("-f", `labels[]=${label}`);
    const created = JSON.parse(this.gh(argumentsList));
    return { number: created.number, id: created.id, title: created.title, url: created.html_url };
  }

  async addSubIssue(repository, parentNumber, childId) {
    const current = JSON.parse(this.gh([
      "api", `repos/${repository}/issues/${parentNumber}/sub_issues?per_page=100`,
    ]));
    if (current.some((issue) => issue.id === childId)) return;
    this.gh([
      "api", "--method", "POST",
      `repos/${repository}/issues/${parentNumber}/sub_issues`,
      "-F", `sub_issue_id=${childId}`,
    ]);
  }

  async addBlocker(repository, issueNumber, blockerId) {
    const current = JSON.parse(this.gh([
      "api", `repos/${repository}/issues/${issueNumber}/dependencies/blocked_by?per_page=100`,
    ]));
    if (current.some((issue) => issue.id === blockerId)) return;
    this.gh([
      "api", "--method", "POST",
      `repos/${repository}/issues/${issueNumber}/dependencies/blocked_by`,
      "-F", `issue_id=${blockerId}`,
    ]);
  }
}

async function main() {
  const { command, options } = parseArguments(process.argv.slice(2));
  if (command === "help") {
    process.stdout.write(`Usage:\n  publish-plan.mjs plan --repository-root <path> --input <file> [--output <file>]\n  publish-plan.mjs apply --plan <file> --approved <plan-id> [--output <file>]\n`);
    return;
  }
  if (command === "plan") {
    const root = resolve(required(options, "repository-root"));
    const [input, config] = await Promise.all([
      jsonFile(required(options, "input")),
      readRepositoryConfig(root),
    ]);
    await emit(createPublishPlan(input, config.value), options.output);
    return;
  }
  if (command === "apply") {
    const plan = await jsonFile(required(options, "plan"));
    await emit(
      await applyPublishPlan(plan, required(options, "approved"), new GhIssueAdapter()),
      options.output,
    );
    return;
  }
  throw new Error(`unknown command '${command}'`);
}

main().catch((error) => {
  process.stderr.write(stableJson({ schemaVersion: 1, error: { name: error.name, message: error.message } }));
  process.exitCode = 1;
});
