#!/usr/bin/env node

import { readFile } from "node:fs/promises";

function option(values, name) {
  const index = values.indexOf(`--${name}`);
  return index === -1 ? null : values[index + 1];
}

const root = new URL("../", import.meta.url);
const packageJson = JSON.parse(await readFile(new URL("package.json", root), "utf8"));
const changesets = JSON.parse(await readFile(new URL(".changeset/config.json", root), "utf8"));
const changelog = await readFile(new URL("CHANGELOG.md", root), "utf8");
const expected = option(process.argv.slice(2), "expected");

if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(packageJson.version)) {
  throw new Error(`invalid package version '${packageJson.version}'`);
}
if (expected && expected !== packageJson.version) {
  throw new Error(`expected version '${expected}', found '${packageJson.version}'`);
}
if (packageJson.private !== true) throw new Error("agent-skills must remain private");
if (Object.hasOwn(packageJson.scripts ?? {}, "publish") || packageJson.publishConfig) {
  throw new Error("private release configuration must not publish to npm");
}
if (!changelog.includes(`## ${packageJson.version}`)) {
  throw new Error(`CHANGELOG.md has no entry for ${packageJson.version}`);
}
if (!Array.isArray(changesets.changelog) || changesets.privatePackages?.version !== true ||
    changesets.privatePackages?.tag !== true) {
  throw new Error("Changesets must create changelogs, version private packages, and allow tags");
}
process.stdout.write(`Release ${packageJson.version} is ready for a private tag.\n`);
