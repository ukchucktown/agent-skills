#!/usr/bin/env node

import { readFile } from "node:fs/promises";

import { validateMattManifest } from "./lib/matt-update.mjs";

const manifest = validateMattManifest(JSON.parse(
  await readFile(new URL("../dependencies/mattpocock.json", import.meta.url), "utf8"),
));
process.stdout.write(`Validated ${Object.keys(manifest.skills).length} Matt skills at ${manifest.revision}.\n`);
