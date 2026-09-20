import assert from "node:assert/strict";
import test from "node:test";

import {
  GitHubMattUpdater,
  renderMattManifest,
  updateMattManifest,
  validateMattManifest,
  validateUpstreamSkill,
} from "../../scripts/lib/matt-update.mjs";

const revision = "a".repeat(40);
const nextRevision = "b".repeat(40);

function manifest(overrides = {}) {
  return {
    schemaVersion: 1,
    repository: "mattpocock/skills",
    branch: "main",
    revision,
    skills: {
      "grill-with-docs": "skills/engineering/grill-with-docs",
      "code-review": "skills/engineering/code-review",
    },
    ...overrides,
  };
}

test("Matt dependency requires an exact commit and sorts selected skills", () => {
  assert.deepEqual(Object.keys(validateMattManifest(manifest()).skills), [
    "code-review",
    "grill-with-docs",
  ]);
  assert.throws(() => validateMattManifest(manifest({ revision: "main" })), /full commit SHA/);
  assert.throws(() => validateMattManifest(manifest({ skills: {} })), /at least one/);
});

test("Matt update changes only the tested revision", () => {
  const updated = updateMattManifest(manifest(), nextRevision);
  assert.equal(updated.revision, nextRevision);
  assert.equal(updated.repository, "mattpocock/skills");
  assert.equal(JSON.parse(renderMattManifest(updated)).revision, nextRevision);
});

test("Matt update validates each upstream skill name", () => {
  assert.equal(validateUpstreamSkill("code-review", "---\nname: code-review\ndescription: Review\n---\n"), true);
  assert.throws(
    () => validateUpstreamSkill("code-review", "---\nname: renamed\n---\n"),
    /frontmatter name changed/,
  );
});

test("GitHub updater uses structured commands and verifies pinned paths", () => {
  const calls = [];
  const runner = (executable, argumentsList, options) => {
    calls.push({ executable, argumentsList, options });
    const endpoint = argumentsList.find((value) => value.startsWith("repos/"));
    if (endpoint?.includes("/commits/")) return JSON.stringify({ sha: nextRevision });
    if (endpoint?.includes("/contents/")) {
      const name = endpoint.includes("code-review") ? "code-review" : "grill-with-docs";
      return JSON.stringify({ content: Buffer.from(`---\nname: ${name}\n---\n`).toString("base64") });
    }
    throw new Error(`unexpected command: ${argumentsList.join(" ")}`);
  };
  const updater = new GitHubMattUpdater("/repository", runner);
  const value = validateMattManifest(manifest());
  assert.equal(updater.latestRevision(value), nextRevision);
  updater.verifyRevision(value, nextRevision);
  assert.equal(calls.length, 3);
  assert.equal(calls.every((call) => call.executable === "gh" && call.options.shell === false), true);
  assert.equal(calls.every((call) => call.options.cwd === "/repository"), true);
});
