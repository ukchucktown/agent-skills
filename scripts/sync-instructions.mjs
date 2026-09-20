#!/usr/bin/env node

import { mkdir, readFile, rename, unlink, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import { readMachineConfig } from "../skills/engineering/sdlc-workflow/scripts/lib/config.mjs";
import { stableJson } from "../skills/engineering/sdlc-workflow/scripts/lib/json.mjs";
import { inspectInstructionSync } from "./lib/instruction-sync.mjs";

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

async function textOrNull(path) {
  try {
    return await readFile(path, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

async function atomicWrite(path, content) {
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.agent-skills-${process.pid}.tmp`;
  try {
    await writeFile(temporary, content, "utf8");
    await rename(temporary, path);
  } catch (error) {
    try { await unlink(temporary); } catch {}
    throw error;
  }
}

async function main() {
  const { command, options } = parseArguments(process.argv.slice(2));
  if (command === "help") {
    process.stdout.write(`Usage:\n  sync-instructions.mjs check --repository <path> [--machine-config <file>]\n  sync-instructions.mjs apply --repository <path> [--machine-config <file>]\n`);
    return;
  }
  if (!new Set(["check", "apply"]).has(command)) throw new Error(`unknown command '${command}'`);
  const repositoryRoot = resolve(required(options, "repository"));
  const profile = await readMachineConfig(repositoryRoot, options["machine-config"]);
  const fragment = await readFile(profile.value.instructionSource, "utf8");
  const paths = [...new Set(Object.values(profile.value.harnesses).map((item) => item.instructionFile))].sort();
  const files = Object.fromEntries(await Promise.all(paths.map(async (path) => [path, await textOrNull(path)])));
  const report = inspectInstructionSync({ fragment, files });
  if (command === "apply") {
    for (const item of report) {
      if (item.status === "drifted") await atomicWrite(item.path, item.desired);
    }
  }
  process.stdout.write(stableJson({
    schemaVersion: 1,
    status: report.some((item) => item.status === "drifted")
      ? (command === "apply" ? "synchronized" : "drifted")
      : "current",
    files: report.map(({ path, status }) => ({ path, status })),
  }));
  if (command === "check" && report.some((item) => item.status === "drifted")) process.exitCode = 2;
}

main().catch((error) => {
  process.stderr.write(stableJson({ schemaVersion: 1, error: { name: error.name, message: error.message } }));
  process.exitCode = 1;
});
