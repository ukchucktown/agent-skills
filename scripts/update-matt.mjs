#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import { stableJson } from "../skills/engineering/sdlc-workflow/scripts/lib/json.mjs";
import {
  GitHubMattUpdater,
  updateMattManifest,
  validateMattManifest,
} from "./lib/matt-update.mjs";

function option(values, name, fallback) {
  const index = values.indexOf(`--${name}`);
  if (index === -1) return fallback;
  if (!values[index + 1]) throw new Error(`--${name} needs a value`);
  return values[index + 1];
}

async function main() {
  if (process.argv.includes("--help") || process.argv.includes("-h")) {
    process.stdout.write("Usage: update-matt.mjs --repository <path> [--manifest <file>]\n");
    return;
  }
  const repositoryRoot = resolve(option(process.argv.slice(2), "repository", "."));
  const manifestFile = resolve(
    repositoryRoot,
    option(process.argv.slice(2), "manifest", "dependencies/mattpocock.json"),
  );
  const manifest = validateMattManifest(JSON.parse(await readFile(manifestFile, "utf8")));
  const updater = new GitHubMattUpdater(repositoryRoot);
  const revision = updater.latestRevision(manifest);
  updater.verifyRevision(manifest, revision);
  if (revision === manifest.revision) {
    process.stdout.write(stableJson({
      schemaVersion: 1,
      status: "current",
      revision,
      skills: Object.keys(manifest.skills),
    }));
    return;
  }
  const updated = updateMattManifest(manifest, revision);
  process.stdout.write(stableJson({
    schemaVersion: 1,
    revision,
    previousRevision: manifest.revision,
    ...updater.createPullRequest(manifest, updated),
  }));
}

main().catch((error) => {
  process.stderr.write(stableJson({ schemaVersion: 1, error: { name: error.name, message: error.message } }));
  process.exitCode = 1;
});
