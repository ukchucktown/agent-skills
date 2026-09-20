import assert from "node:assert/strict";
import { lstat, mkdir, mkdtemp, readFile, readlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";

import { machineDefaults, validateMachineConfig } from "../../skills/engineering/sdlc-workflow/scripts/lib/config.mjs";
import {
  applyBootstrapPlan,
  createBootstrapPlan,
  inspectBootstrap,
} from "../../scripts/lib/bootstrap.mjs";
import {
  inspectInstructionSync,
  syncInstructionContent,
} from "../../scripts/lib/instruction-sync.mjs";

async function fixture(context) {
  const root = await mkdtemp(join(tmpdir(), "agent-skills-bootstrap-"));
  context.after(async () => {
    const { rm } = await import("node:fs/promises");
    await rm(root, { recursive: true, force: true });
  });
  const repository = join(root, "Github", "agent-skills");
  const home = join(root, "home");
  for (const skill of ["first-read", "sdlc-plan-work"]) {
    const bucket = skill === "first-read" ? "writing" : "engineering";
    const path = join(repository, "skills", bucket, skill);
    await mkdir(path, { recursive: true });
    await writeFile(join(path, "SKILL.md"), `---\nname: ${skill}\ndescription: fixture\n---\n`);
  }
  await mkdir(join(repository, "instructions"), { recursive: true });
  await writeFile(join(repository, "instructions", "global.md"), "Use the personal workflow.\n");
  const defaults = machineDefaults(repository, home);
  const profile = validateMachineConfig({
    ...defaults,
    worktreeManager: "supacode",
    lampwrightStateRoot: join(home, ".local", "state", "lampwright"),
  }, repository);
  return {
    root,
    repository,
    home,
    profile,
    configFile: join(home, ".config", "agent-skills", "config.json"),
  };
}

async function disableTargets(profile, skill) {
  const paths = [...new Set(Object.values(profile.harnesses).map((harness) =>
    join(harness.skillRoot, skill)))].sort();
  const entry = join(profile.lampwrightStateRoot, "disabled-storage", "v1", "entries", "disabled-1");
  await mkdir(entry, { recursive: true });
  await writeFile(join(entry, "manifest.json"), JSON.stringify({
    schemaVersion: 2,
    artifacts: paths.map((path) => ({ originalLocation: { path } })),
  }));
  return paths;
}

test("instruction sync preserves unrelated content and reports drift", () => {
  const current = "# Existing\n\nKeep this.\n";
  const desired = syncInstructionContent(current, "Use the workflow.\n");
  assert.match(desired, /^# Existing\n\nKeep this\./);
  assert.match(desired, /agent-skills:global-instructions:start/);
  const report = inspectInstructionSync({ fragment: "Use the workflow.\n", files: { "/a": current } });
  assert.equal(report[0].status, "drifted");
  assert.equal(
    inspectInstructionSync({ fragment: "Use the workflow.\n", files: { "/a": desired } })[0].status,
    "current",
  );
});

test("instruction sync preserves CRLF content outside its managed block", () => {
  const current = "# Existing\r\n\r\nKeep this.\r\n";
  const desired = syncInstructionContent(current, "Use the workflow.\n");
  assert.equal(desired.startsWith(current), true);
  assert.equal(desired.replaceAll("\r\n", "").includes("\n"), false);
});

test("bootstrap writes a profile, syncs instructions, and links promoted skills", async (context) => {
  const value = await fixture(context);
  const codexInstructions = value.profile.harnesses.codex.instructionFile;
  await mkdir(dirname(codexInstructions), { recursive: true });
  await writeFile(codexInstructions, "# Existing Codex rules\n");
  const snapshot = await inspectBootstrap({
    profile: value.profile,
    selectedSkills: null,
    configFile: value.configFile,
    profileExists: false,
  });
  const plan = createBootstrapPlan(value.profile, snapshot);
  assert.equal(plan.report.conflicts.length, 0);
  assert.equal(plan.report.instructionDrift.length, 3);
  assert.equal(plan.actions.filter((action) => action.type === "create-link").length, 4);

  const result = await applyBootstrapPlan(plan);
  assert.equal(result.status, "applied");
  assert.equal(JSON.parse(await readFile(value.configFile, "utf8")).worktreeManager, "supacode");
  assert.match(await readFile(codexInstructions, "utf8"), /^# Existing Codex rules/);
  for (const harness of Object.values(value.profile.harnesses)) {
    for (const skill of ["first-read", "sdlc-plan-work"]) {
      const target = join(harness.skillRoot, skill);
      assert.equal((await lstat(target)).isSymbolicLink(), true);
      assert.equal(resolve(dirname(target), await readlink(target)).endsWith(skill), true);
    }
  }

  const current = await inspectBootstrap({
    profile: value.profile,
    selectedSkills: null,
    configFile: value.configFile,
    profileExists: true,
  });
  assert.equal(createBootstrapPlan(value.profile, current).actions.length, 0);
});

test("bootstrap does not recreate Lampwright-disabled installations", async (context) => {
  const value = await fixture(context);
  const disabled = await disableTargets(value.profile, "first-read");
  const snapshot = await inspectBootstrap({
    profile: value.profile,
    selectedSkills: ["first-read"],
    configFile: value.configFile,
    profileExists: false,
  });
  const plan = createBootstrapPlan(value.profile, snapshot);
  assert.deepEqual(plan.report.disabled, disabled);
  assert.equal(plan.actions.some((action) => action.type === "create-link"), false);
  await applyBootstrapPlan(plan);
  for (const target of disabled) {
    await assert.rejects(() => lstat(target), { code: "ENOENT" });
  }
});

test("bootstrap stops on an unreadable Lampwright disabled manifest", async (context) => {
  const value = await fixture(context);
  const entry = join(value.profile.lampwrightStateRoot, "disabled-storage", "v1", "entries", "broken");
  await mkdir(entry, { recursive: true });
  await writeFile(join(entry, "manifest.json"), "not json");
  await assert.rejects(() => inspectBootstrap({
    profile: value.profile,
    selectedSkills: ["first-read"],
    configFile: value.configFile,
    profileExists: false,
  }), /invalid Lampwright disabled manifest/);
});

test("selective bootstrap leaves occupied targets unchanged", async (context) => {
  const value = await fixture(context);
  const workflow = join(value.repository, "skills", "engineering", "sdlc-workflow");
  await mkdir(workflow, { recursive: true });
  await writeFile(join(workflow, "SKILL.md"), "---\nname: sdlc-workflow\ndescription: fixture\n---\n");
  const target = join(value.profile.harnesses.codex.skillRoot, "sdlc-plan-work");
  await mkdir(target, { recursive: true });
  const snapshot = await inspectBootstrap({
    profile: value.profile,
    selectedSkills: ["sdlc-plan-work"],
    configFile: value.configFile,
    profileExists: false,
  });
  const plan = createBootstrapPlan(value.profile, snapshot);
  assert.deepEqual(plan.report.conflicts, [target]);
  assert.equal(plan.actions.some((action) => action.target === target), false);
  assert.equal(plan.evidence.links.some((item) => item.target.endsWith("first-read")), false);
  assert.equal(plan.evidence.links.some((item) => item.target.endsWith("sdlc-workflow")), true);
});

test("selective bootstrap adds the shared runtime for an SDLC entry point", async (context) => {
  const value = await fixture(context);
  const workflow = join(value.repository, "skills", "engineering", "sdlc-workflow");
  await mkdir(workflow, { recursive: true });
  await writeFile(join(workflow, "SKILL.md"), "---\nname: sdlc-workflow\ndescription: fixture\n---\n");
  const snapshot = await inspectBootstrap({
    profile: value.profile,
    selectedSkills: ["sdlc-plan-work"],
    configFile: value.configFile,
    profileExists: false,
  });
  const linkedNames = new Set(snapshot.links.map((item) => item.name));
  assert.deepEqual(linkedNames, new Set(["sdlc-plan-work", "sdlc-workflow"]));
});

test("bootstrap rejects stale evidence before any mutation", async (context) => {
  const value = await fixture(context);
  const snapshot = await inspectBootstrap({
    profile: value.profile,
    selectedSkills: ["first-read"],
    configFile: value.configFile,
    profileExists: false,
  });
  const plan = createBootstrapPlan(value.profile, snapshot);
  const changedInstruction = value.profile.harnesses.claude.instructionFile;
  await mkdir(dirname(changedInstruction), { recursive: true });
  await writeFile(changedInstruction, "changed after plan\n");
  await assert.rejects(() => applyBootstrapPlan(plan), /stale/);
  await assert.rejects(() => readFile(value.configFile), { code: "ENOENT" });
});
