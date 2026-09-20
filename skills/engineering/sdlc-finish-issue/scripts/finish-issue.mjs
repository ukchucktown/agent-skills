#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import { readRepositoryConfig } from "../../sdlc-workflow/scripts/lib/config.mjs";
import { stableJson } from "../../sdlc-workflow/scripts/lib/json.mjs";
import { GitFinishAdapter, GitHubFinishAdapter } from "./lib/adapters.mjs";
import {
  assertFinishCandidate,
  finishIssue,
  runValidationCommands,
} from "./lib/finisher.mjs";
import { FinishInspector } from "./lib/inspector.mjs";

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

async function candidate(options) {
  const repositoryRoot = resolve(required(options, "repository"));
  const issue = Number.parseInt(required(options, "issue"), 10);
  if (!Number.isInteger(issue)) throw new Error("--issue must be an integer");
  const repository = await readRepositoryConfig(repositoryRoot);
  const inspector = new FinishInspector(repositoryRoot, repository.value);
  const snapshot = await inspector.inspect(issue);
  assertFinishCandidate(snapshot, repository.value);
  const validation = runValidationCommands({
    commands: repository.value.childValidationCommands,
    repositoryRoot,
    candidateCommit: snapshot.candidateCommit,
  });
  return { repositoryRoot, repository: repository.value, inspector, snapshot, validation };
}

async function main() {
  const { command, options } = parseArguments(process.argv.slice(2));
  if (command === "help") {
    process.stdout.write(`Usage:\n  finish-issue.mjs prepare --repository <path> --issue <number> [--output <file>]\n  finish-issue.mjs finish --repository <path> --issue <number> --standards-review <file> --specification-review <file> [--output <file>]\n`);
    return;
  }
  if (command === "prepare") {
    const current = await candidate(options);
    await emit({
      schemaVersion: 1,
      issue: current.snapshot.issue.number,
      branch: current.snapshot.branch,
      integrationBranch: current.snapshot.integrationBranch,
      candidateCommit: current.snapshot.candidateCommit,
      validation: current.validation,
      reviewEvidence: {
        standards: {
          schemaVersion: 1,
          axis: "standards",
          candidateCommit: current.snapshot.candidateCommit,
          verdict: "fail",
          summary: "Pending standards review. Replace this summary and verdict after review.",
        },
        specification: {
          schemaVersion: 1,
          axis: "specification",
          candidateCommit: current.snapshot.candidateCommit,
          verdict: "fail",
          summary: "Pending specification review. Replace this summary and verdict after review.",
        },
      },
    }, options.output);
    return;
  }
  if (command === "finish") {
    const current = await candidate(options);
    const result = await finishIssue({
      snapshot: current.snapshot,
      config: current.repository,
      validation: current.validation,
      standardsReview: await jsonFile(required(options, "standards-review")),
      specificationReview: await jsonFile(required(options, "specification-review")),
      git: new GitFinishAdapter(current.repositoryRoot),
      github: new GitHubFinishAdapter(current.repositoryRoot),
    });
    await emit(result, options.output);
    return;
  }
  throw new Error(`unknown command '${command}'`);
}

main().catch((error) => {
  process.stderr.write(stableJson({ schemaVersion: 1, error: { name: error.name, message: error.message } }));
  process.exitCode = 1;
});
