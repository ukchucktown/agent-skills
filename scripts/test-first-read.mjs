#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const candidates = process.platform === "win32" ? ["py", "python"] : ["python3", "python"];

for (const executable of candidates) {
  const probe = spawnSync(executable, ["--version"], { encoding: "utf8" });
  if (probe.error || probe.status !== 0) continue;
  const result = spawnSync(executable, ["tests/first-read/test_lint.py"], {
    cwd: repositoryRoot,
    encoding: "utf8",
    stdio: "inherit",
  });
  process.exit(result.status ?? 1);
}

console.error("First Read tests need Python 3.8 or later.");
process.exit(1);
