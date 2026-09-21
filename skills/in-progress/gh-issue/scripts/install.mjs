#!/usr/bin/env node

import { lstatSync, mkdirSync, readlinkSync, symlinkSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

function parseArguments(argv) {
  const options = { dryRun: false, home: homedir(), source: null };
  const args = [...argv];
  while (args.length > 0) {
    const value = args.shift();
    if (value === "--dry-run") options.dryRun = true;
    else if (value === "--home" || value === "--source") {
      const path = args.shift();
      if (!path) throw new Error(`${value} requires a path.`);
      if (value === "--home") options.home = resolve(path);
      else options.source = resolve(path);
    }
    else if (value === "--help" || value === "-h") options.help = true;
    else throw new Error(`Unexpected argument: ${value}`);
  }
  return options;
}

function exists(path) {
  try {
    return lstatSync(path);
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

function linkPlan(target, source) {
  const stat = exists(target);
  if (!stat) return { action: "create", target, source };
  if (!stat.isSymbolicLink()) {
    return { action: "conflict", target, source, reason: "target is not a symbolic link" };
  }

  const actual = resolve(dirname(target), readlinkSync(target));
  if (actual === resolve(source)) return { action: "unchanged", target, source };
  return {
    action: "conflict",
    target,
    source,
    reason: `target links to ${actual}`,
  };
}

export function createInstallPlan({ home, source }) {
  const sourceStat = exists(source);
  if (!sourceStat?.isDirectory() || !exists(join(source, "SKILL.md"))) {
    throw new Error(`${source} is not a skill directory with a SKILL.md file.`);
  }
  const agentTarget = join(home, ".agents", "skills", "gh-issue");
  const claudeTarget = join(home, ".claude", "skills", "gh-issue");
  return {
    source,
    adapters: {
      codex: agentTarget,
      claude: claudeTarget,
      copilot: agentTarget,
    },
    links: [
      linkPlan(agentTarget, source),
      linkPlan(claudeTarget, agentTarget),
    ],
  };
}

export function applyInstallPlan(plan) {
  const conflict = plan.links.find((entry) => entry.action === "conflict");
  if (conflict) throw new Error(`${conflict.target}: ${conflict.reason}`);

  for (const entry of plan.links) {
    if (entry.action !== "create") continue;
    mkdirSync(dirname(entry.target), { recursive: true });
    const linkTarget = process.platform === "win32"
      ? resolve(entry.source)
      : relative(dirname(entry.target), entry.source);
    symlinkSync(linkTarget, entry.target, process.platform === "win32" ? "junction" : "dir");
  }
}

function usage() {
  return `Usage: node install.mjs [--dry-run] [--home PATH] [--source PATH]

Links gh-issue into ~/.agents/skills for Codex and Copilot, then links Claude
Code to the same installation. Existing non-matching targets are preserved.`;
}

async function main() {
  try {
    const options = parseArguments(process.argv.slice(2));
    if (options.help) {
      process.stdout.write(`${usage()}\n`);
      return;
    }

    const source = options.source ?? resolve(dirname(fileURLToPath(import.meta.url)), "..");
    const plan = createInstallPlan({ home: options.home, source });
    if (!options.dryRun) applyInstallPlan(plan);
    process.stdout.write(`${JSON.stringify({ ...plan, applied: !options.dryRun }, null, 2)}\n`);
  } catch (error) {
    process.stderr.write(`gh-issue install: ${error.message}\n`);
    process.exitCode = 1;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
