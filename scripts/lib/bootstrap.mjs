import { createHash } from "node:crypto";
import {
  lstat,
  mkdir,
  readFile,
  readlink,
  readdir,
  rename,
  symlink,
  unlink,
  writeFile,
} from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";

import { fingerprint } from "../../skills/engineering/sdlc-workflow/scripts/lib/json.mjs";
import { inspectInstructionSync } from "./instruction-sync.mjs";

function digest(value) {
  return value === null
    ? null
    : createHash("sha256").update(value).digest("hex");
}

async function textOrNull(path) {
  try {
    return await readFile(path, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

async function pathState(path) {
  try {
    const stats = await lstat(path);
    if (!stats.isSymbolicLink()) return { kind: "occupied" };
    const target = await readlink(path);
    return { kind: "link", target: resolve(dirname(path), target) };
  } catch (error) {
    if (error.code === "ENOENT") return { kind: "absent" };
    throw error;
  }
}

export async function discoverPromotedSkills(skillSourceRoot) {
  const skills = [];
  for (const bucket of ["engineering", "writing"]) {
    const bucketRoot = join(skillSourceRoot, bucket);
    let entries;
    try {
      entries = await readdir(bucketRoot, { withFileTypes: true });
    } catch (error) {
      if (error.code === "ENOENT") continue;
      throw error;
    }
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      const source = join(bucketRoot, entry.name);
      if (await textOrNull(join(source, "SKILL.md")) !== null) {
        skills.push({ name: entry.name, source: resolve(source) });
      }
    }
  }
  return skills.sort((left, right) => left.name.localeCompare(right.name));
}

function disabledLocations(manifest, file) {
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    throw new Error(`invalid Lampwright disabled manifest '${file}'`);
  }
  if (manifest.schemaVersion === 1) {
    if (typeof manifest.originalLocation?.path !== "string") {
      throw new Error(`invalid Lampwright disabled manifest '${file}'`);
    }
    return [manifest.originalLocation.path];
  }
  if (manifest.schemaVersion === 2) {
    if (!Array.isArray(manifest.artifacts) || manifest.artifacts.length === 0 ||
        manifest.artifacts.some((artifact) => typeof artifact?.originalLocation?.path !== "string")) {
      throw new Error(`invalid Lampwright disabled manifest '${file}'`);
    }
    return manifest.artifacts.map((artifact) => artifact.originalLocation.path);
  }
  throw new Error(`unsupported Lampwright disabled manifest '${file}'`);
}

export async function lampwrightDisabledPaths(stateRoot) {
  const entriesRoot = join(stateRoot, "disabled-storage", "v1", "entries");
  let entries;
  try {
    entries = await readdir(entriesRoot, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") return new Set();
    throw error;
  }
  const paths = new Set();
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const file = join(entriesRoot, entry.name, "manifest.json");
    const raw = await textOrNull(file);
    if (raw === null) throw new Error(`missing Lampwright disabled manifest '${file}'`);
    let manifest;
    try {
      manifest = JSON.parse(raw);
    } catch (error) {
      throw new Error(`invalid Lampwright disabled manifest '${file}'`, { cause: error });
    }
    for (const path of disabledLocations(manifest, file)) {
      if (!isAbsolute(path)) throw new Error(`Lampwright disabled path is not absolute in '${file}'`);
      paths.add(resolve(path));
    }
  }
  return paths;
}

function targetMap(skills, harnesses) {
  const targets = new Map();
  for (const [harness, settings] of Object.entries(harnesses)) {
    for (const skill of skills) {
      const target = resolve(settings.skillRoot, skill.name);
      const current = targets.get(target) ?? { ...skill, target, harnesses: [] };
      current.harnesses.push(harness);
      targets.set(target, current);
    }
  }
  return [...targets.values()]
    .map((item) => ({ ...item, harnesses: item.harnesses.sort() }))
    .sort((left, right) => left.target.localeCompare(right.target));
}

export async function inspectBootstrap({ profile, selectedSkills, configFile, profileExists }) {
  const discovered = await discoverPromotedSkills(profile.skillSourceRoot);
  const requested = selectedSkills?.length ? new Set(selectedSkills) : null;
  if (requested && [...requested].some((name) => name.startsWith("sdlc-") && name !== "sdlc-workflow")) {
    requested.add("sdlc-workflow");
  }
  const skills = requested ? discovered.filter((skill) => requested.has(skill.name)) : discovered;
  if (requested) {
    const missing = [...requested].filter((name) => !skills.some((skill) => skill.name === name));
    if (missing.length > 0) throw new Error(`unknown promoted skill(s): ${missing.sort().join(", ")}`);
  }
  const disabled = await lampwrightDisabledPaths(profile.lampwrightStateRoot);
  const links = [];
  for (const target of targetMap(skills, profile.harnesses)) {
    const state = await pathState(target.target);
    let status;
    if (disabled.has(target.target)) status = "disabled-by-lampwright";
    else if (state.kind === "absent") status = "missing";
    else if (state.kind === "link" && state.target === target.source) status = "linked";
    else status = "conflict";
    links.push({ ...target, state, status });
  }
  const fragment = await readFile(profile.instructionSource, "utf8");
  const instructionFiles = Object.fromEntries(await Promise.all(
    [...new Set(Object.values(profile.harnesses).map((item) => item.instructionFile))]
      .sort()
      .map(async (path) => [path, await textOrNull(path)]),
  ));
  const instructions = inspectInstructionSync({ fragment, files: instructionFiles });
  const currentConfig = await textOrNull(configFile);
  return {
    schemaVersion: 1,
    profileExists,
    configFile: resolve(configFile),
    currentConfigHash: digest(currentConfig),
    links,
    instructions,
  };
}

function planContent(profile, snapshot) {
  const actions = [];
  if (!snapshot.profileExists) {
    actions.push({
      type: "write-file",
      path: snapshot.configFile,
      expectedHash: snapshot.currentConfigHash,
      content: `${JSON.stringify(profile, null, 2)}\n`,
    });
  }
  for (const instruction of snapshot.instructions) {
    if (instruction.status === "drifted") {
      actions.push({
        type: "write-file",
        path: instruction.path,
        expectedHash: digest(instruction.current),
        content: instruction.desired,
      });
    }
  }
  for (const link of snapshot.links) {
    if (link.status === "missing") {
      actions.push({
        type: "create-link",
        source: link.source,
        target: link.target,
        harnesses: link.harnesses,
      });
    }
  }
  return {
    schemaVersion: 1,
    operation: "bootstrap",
    profile,
    evidence: {
      configFile: snapshot.configFile,
      currentConfigHash: snapshot.currentConfigHash,
      links: snapshot.links.map((link) => ({
        target: link.target,
        source: link.source,
        status: link.status,
        state: link.state,
      })),
      instructions: snapshot.instructions.map((item) => ({
        path: item.path,
        currentHash: digest(item.current),
      })),
    },
    report: {
      linked: snapshot.links.filter((item) => item.status === "linked").map((item) => item.target),
      disabled: snapshot.links.filter((item) => item.status === "disabled-by-lampwright").map((item) => item.target),
      conflicts: snapshot.links.filter((item) => item.status === "conflict").map((item) => item.target),
      instructionDrift: snapshot.instructions.filter((item) => item.status === "drifted").map((item) => item.path),
    },
    actions,
  };
}

export function createBootstrapPlan(profile, snapshot) {
  const content = planContent(profile, snapshot);
  return { ...content, planId: fingerprint(content) };
}

async function atomicWrite(path, content) {
  await mkdir(dirname(path), { recursive: true });
  const temporary = join(dirname(path), `.agent-skills-${process.pid}-${Date.now()}.tmp`);
  try {
    await writeFile(temporary, content, "utf8");
    await rename(temporary, path);
  } catch (error) {
    try { await unlink(temporary); } catch {}
    throw error;
  }
}

export async function applyBootstrapPlan(plan) {
  const expected = { ...plan };
  delete expected.planId;
  if (fingerprint(expected) !== plan.planId) throw new Error("bootstrap plan content changed");
  const receipts = [];
  const disabled = await lampwrightDisabledPaths(plan.profile.lampwrightStateRoot);
  for (const action of plan.actions) {
    if (action.type === "write-file") {
      const current = await textOrNull(action.path);
      if (digest(current) !== action.expectedHash) {
        throw new Error(`bootstrap plan is stale for '${action.path}'`);
      }
    } else if (action.type === "create-link") {
      if (!disabled.has(resolve(action.target))) {
        const state = await pathState(action.target);
        if (state.kind !== "absent") throw new Error(`bootstrap link target changed: '${action.target}'`);
      }
    } else {
      throw new Error(`unsupported bootstrap action '${action.type}'`);
    }
  }
  for (const action of plan.actions) {
    if (action.type === "write-file") {
      await atomicWrite(action.path, action.content);
      receipts.push({ type: action.type, path: action.path });
    } else if (action.type === "create-link") {
      if (disabled.has(resolve(action.target))) {
        receipts.push({ type: action.type, target: action.target, status: "skipped-disabled" });
        continue;
      }
      await mkdir(dirname(action.target), { recursive: true });
      const target = process.platform === "win32" ? action.source : relative(dirname(action.target), action.source);
      await symlink(target, action.target, process.platform === "win32" ? "junction" : "dir");
      receipts.push({ type: action.type, target: action.target, status: "linked" });
    }
  }
  return { schemaVersion: 1, status: "applied", planId: plan.planId, receipts, report: plan.report };
}
