#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const candidates = process.platform === "win32" ? ["py", "python"] : ["python3", "python"];
let python;

for (const candidate of candidates) {
  const probe = spawnSync(candidate, ["--version"], { encoding: "utf8" });
  if (!probe.error && probe.status === 0) {
    python = candidate;
    break;
  }
}

if (!python) {
  console.error("Prompt validation needs Python 3.8 or later.");
  process.exit(1);
}

const promptPath = resolve(repositoryRoot, "docs/first-read/PROMPT.md");
const before = readFileSync(promptPath, "utf8");
const build = spawnSync(python, ["tools/first-read/build_prompt.py"], {
  cwd: repositoryRoot,
  encoding: "utf8",
  stdio: "inherit",
});
if (build.status !== 0) process.exit(build.status ?? 1);

const after = readFileSync(promptPath, "utf8");
if (before !== after) {
  console.error("docs/first-read/PROMPT.md is stale. Rebuild and commit it.");
  process.exit(1);
}

console.log("The generated First Read prompt is current.");
