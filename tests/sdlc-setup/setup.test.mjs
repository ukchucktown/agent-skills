import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { readRepositoryConfig } from "../../skills/engineering/sdlc-workflow/scripts/lib/config.mjs";
import {
  applySetupPlan,
  createSetupPlan,
  managedPaths,
  NodeFileAdapter,
  snapshotFiles,
} from "../../skills/engineering/sdlc-setup/scripts/lib/setup-core.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const templateRoot = join(
  repositoryRoot,
  "skills",
  "engineering",
  "sdlc-setup",
  "templates",
);

class FakeLabels {
  constructor(repository = "example/widgets", labels = []) {
    this.repository = repository;
    this.labels = structuredClone(labels);
    this.writes = [];
  }

  async snapshot() {
    return { repository: this.repository, labels: structuredClone(this.labels) };
  }

  async ensureLabel(label) {
    this.writes.push(structuredClone(label));
    this.labels = this.labels.filter((current) => current.name !== label.name);
    this.labels.push(structuredClone(label));
  }
}

async function templates() {
  const paths = managedPaths.filter((file) => file.startsWith(".github/workflows/") ||
    file.startsWith(".github/scripts/"));
  return Object.fromEntries(await Promise.all(paths.map(async (file) => [
    file,
    await readFile(join(templateRoot, file), "utf8"),
  ])));
}

async function fixture() {
  const directory = await mkdtemp(join(tmpdir(), "agent-skills-setup-"));
  const repository = join(directory, "widgets");
  await mkdir(repository, { recursive: true });
  execFileSync("git", ["init", "--initial-branch=develop", repository], { stdio: "ignore" });
  await writeFile(
    join(repository, "AGENTS.md"),
    "# Repository rules\n\nUse ask-matt before a large refactor.\n",
  );
  await writeFile(
    join(repository, "CLAUDE.md"),
    "# Claude notes\n\nKeep the repository-specific release checklist.\n",
  );
  await mkdir(join(repository, ".agents", "skills", "grilling"), { recursive: true });
  await writeFile(
    join(repository, ".agents", "skills", "grilling", "SKILL.md"),
    "---\nname: grilling\ndescription: Test fixture\n---\n",
  );
  return { directory, repository };
}

const settings = {
  stableBranch: "develop",
  integrationBranchPattern: "integrate/feature-{issue}-{slug}",
  childBranchPattern: "work/issue-{issue}-{slug}",
  childMergeMethod: "squash",
  featureMergeMethod: "merge",
  validationSetupCommands: [{ executable: "npm", args: ["ci", "--ignore-scripts"] }],
  childValidationCommands: [{ executable: "npm", args: ["test", "--", "--unit"] }],
  featureValidationCommands: [{ executable: "npm", args: ["test"] }],
};

test("setup preserves repository instructions and becomes idempotent", async (context) => {
  const currentFixture = await fixture();
  context.after(() => rm(currentFixture.directory, { recursive: true, force: true }));
  const fileAdapter = new NodeFileAdapter(currentFixture.repository);
  const github = new FakeLabels();
  const templateValues = await templates();
  const before = await snapshotFiles(fileAdapter);
  const plan = createSetupPlan({
    repositoryRoot: currentFixture.repository,
    settings,
    files: before,
    labels: await github.snapshot(),
    templates: templateValues,
    mattLocations: await fileAdapter.detectMattConfiguration(),
  });

  assert.deepEqual(
    plan.detections.mattConfiguration,
    [".agents/skills/grilling", "AGENTS.md"],
  );
  assert.equal(await fileAdapter.read("docs/agents/sdlc.md"), null);
  assert.ok(plan.actions.some((action) => action.id === "label-featureLabel"));

  const report = await applySetupPlan({ plan, fileAdapter, githubAdapter: github });
  assert.equal(report.status, "applied");
  assert.equal(github.writes.length, 3);

  const agents = await fileAdapter.read("AGENTS.md");
  const claude = await fileAdapter.read("CLAUDE.md");
  assert.match(agents, /Use ask-matt before a large refactor\./);
  assert.match(agents, /Coordinated feature workflow/);
  assert.match(claude, /Keep the repository-specific release checklist\./);
  assert.match(claude, /@AGENTS\.md/);

  const config = await readRepositoryConfig(currentFixture.repository);
  assert.equal(config.value.stableBranch, "develop");
  assert.equal(config.value.childMergeMethod, "squash");
  assert.deepEqual(config.value.validationSetupCommands, settings.validationSetupCommands);
  assert.deepEqual(config.value.childValidationCommands, settings.childValidationCommands);

  const after = await snapshotFiles(fileAdapter);
  const second = createSetupPlan({
    repositoryRoot: currentFixture.repository,
    settings,
    files: after,
    labels: await github.snapshot(),
    templates: templateValues,
  });
  assert.deepEqual(second.actions, []);
});

test("setup rejects a plan after an instruction file changes", async (context) => {
  const currentFixture = await fixture();
  context.after(() => rm(currentFixture.directory, { recursive: true, force: true }));
  const fileAdapter = new NodeFileAdapter(currentFixture.repository);
  const github = new FakeLabels();
  const plan = createSetupPlan({
    repositoryRoot: currentFixture.repository,
    settings,
    files: await snapshotFiles(fileAdapter),
    labels: await github.snapshot(),
    templates: await templates(),
  });
  await writeFile(join(currentFixture.repository, "AGENTS.md"), "Changed after planning.\n");

  await assert.rejects(
    applySetupPlan({ plan, fileAdapter, githubAdapter: github }),
    /setup plan is stale/,
  );
  assert.deepEqual(github.writes, []);
  assert.equal(await fileAdapter.read("docs/agents/sdlc.md"), null);
});

test("an existing thin Claude pointer is not duplicated", async (context) => {
  const currentFixture = await fixture();
  context.after(() => rm(currentFixture.directory, { recursive: true, force: true }));
  await writeFile(join(currentFixture.repository, "CLAUDE.md"), "@AGENTS.md\n");
  const fileAdapter = new NodeFileAdapter(currentFixture.repository);
  const plan = createSetupPlan({
    repositoryRoot: currentFixture.repository,
    settings,
    files: await snapshotFiles(fileAdapter),
    labels: await new FakeLabels().snapshot(),
    templates: await templates(),
  });
  assert.ok(!plan.actions.some((action) => action.parameters.path === "CLAUDE.md"));
});
