#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { isAbsolute, join, resolve } from "node:path";

import {
  machineDefaults,
  validateMachineConfig,
} from "../skills/engineering/sdlc-workflow/scripts/lib/config.mjs";
import { stableJson } from "../skills/engineering/sdlc-workflow/scripts/lib/json.mjs";
import {
  applyBootstrapPlan,
  createBootstrapPlan,
  inspectBootstrap,
} from "./lib/bootstrap.mjs";

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

function defaultLampwrightState(home, environment = process.env) {
  if (environment.XDG_STATE_HOME && isAbsolute(environment.XDG_STATE_HOME)) {
    return join(environment.XDG_STATE_HOME, "lampwright");
  }
  if (process.platform === "win32") {
    return join(environment.LOCALAPPDATA || environment.APPDATA || join(home, "AppData", "Local"), "lampwright");
  }
  return join(home, ".local", "state", "lampwright");
}

async function profileFor(repositoryRoot, home, configFile, options) {
  try {
    return {
      exists: true,
      value: validateMachineConfig(await jsonFile(configFile), repositoryRoot),
    };
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const defaults = machineDefaults(repositoryRoot, home);
  const profile = validateMachineConfig({
    ...defaults,
    worktreeManager: options["worktree-manager"] ?? "supacode",
    lampwrightStateRoot: options["lampwright-state"] ?? defaultLampwrightState(home),
  }, repositoryRoot);
  return { exists: false, value: profile };
}

async function main() {
  const { command, options } = parseArguments(process.argv.slice(2));
  if (command === "help") {
    process.stdout.write(`Usage:\n  bootstrap.mjs plan --repository <path> [--home <path>] [--config <file>] [--skills <comma-list>] [--worktree-manager <supacode|git>] [--lampwright-state <path>] [--output <file>]\n  bootstrap.mjs apply --plan <file> [--output <file>]\n`);
    return;
  }
  if (command === "plan") {
    const repositoryRoot = resolve(required(options, "repository"));
    const home = resolve(options.home ?? homedir());
    const configFile = resolve(options.config ?? join(home, ".config", "agent-skills", "config.json"));
    const profile = await profileFor(repositoryRoot, home, configFile, options);
    const selectedSkills = options.skills
      ? options.skills.split(",").map((item) => item.trim()).filter(Boolean)
      : null;
    const snapshot = await inspectBootstrap({
      profile: profile.value,
      selectedSkills,
      configFile,
      profileExists: profile.exists,
    });
    await emit(createBootstrapPlan(profile.value, snapshot), options.output);
    return;
  }
  if (command === "apply") {
    await emit(await applyBootstrapPlan(await jsonFile(required(options, "plan"))), options.output);
    return;
  }
  throw new Error(`unknown command '${command}'`);
}

main().catch((error) => {
  process.stderr.write(stableJson({ schemaVersion: 1, error: { name: error.name, message: error.message } }));
  process.exitCode = 1;
});
