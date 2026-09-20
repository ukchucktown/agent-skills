#!/usr/bin/env node

import { readdir, readFile, stat } from "node:fs/promises";
import { dirname, extname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const skillsRoot = join(repositoryRoot, "skills");
const allowedBuckets = new Set([
  "deprecated",
  "engineering",
  "in-progress",
  "writing",
]);
const errors = [];

async function filesBelow(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(
    entries
      .filter((entry) => entry.name !== ".git" && entry.name !== "node_modules")
      .map(async (entry) => {
        const fullPath = join(directory, entry.name);
        return entry.isDirectory() ? filesBelow(fullPath) : [fullPath];
      }),
  );
  return nested.flat();
}

function display(file) {
  return relative(repositoryRoot, file).split(sep).join("/");
}

function parseFrontmatter(text, file) {
  if (!text.startsWith("---\n")) {
    errors.push(`${display(file)}: missing YAML frontmatter`);
    return new Map();
  }

  const end = text.indexOf("\n---\n", 4);
  if (end === -1) {
    errors.push(`${display(file)}: frontmatter has no closing delimiter`);
    return new Map();
  }

  const values = new Map();
  for (const line of text.slice(4, end).split("\n")) {
    if (!line.trim() || line.trimStart().startsWith("#")) continue;
    const separator = line.indexOf(":");
    if (separator === -1) {
      errors.push(`${display(file)}: invalid frontmatter line: ${line}`);
      continue;
    }
    values.set(line.slice(0, separator).trim(), line.slice(separator + 1).trim());
  }
  return values;
}

async function validateSkills(files) {
  const skillFiles = files.filter((file) => file.endsWith(`${sep}SKILL.md`));
  const names = new Map();

  for (const file of skillFiles) {
    const parts = relative(skillsRoot, file).split(sep);
    if (parts.length !== 3) {
      errors.push(
        `${display(file)}: expected skills/<bucket>/<skill>/SKILL.md`,
      );
      continue;
    }

    const [bucket, directoryName] = parts;
    if (!allowedBuckets.has(bucket)) {
      errors.push(`${display(file)}: unknown lifecycle bucket '${bucket}'`);
    }

    const metadata = parseFrontmatter(await readFile(file, "utf8"), file);
    const name = metadata.get("name");
    const description = metadata.get("description");
    if (!name) errors.push(`${display(file)}: frontmatter needs a name`);
    if (!description) errors.push(`${display(file)}: frontmatter needs a description`);
    if (name && name !== directoryName) {
      errors.push(
        `${display(file)}: name '${name}' must match directory '${directoryName}'`,
      );
    }
    if (name && names.has(name)) {
      errors.push(
        `${display(file)}: duplicate skill name '${name}' also appears in ${names.get(name)}`,
      );
    } else if (name) {
      names.set(name, display(file));
    }
  }

  if (skillFiles.length === 0) errors.push("skills/: no SKILL.md files found");
  return skillFiles.length;
}

function markdownTargets(text) {
  const targets = [];
  const linkPattern = /!?\[[^\]]*\]\((<[^>]+>|[^)\s]+)(?:\s+["'][^"']*["'])?\)/g;
  for (const match of text.matchAll(linkPattern)) {
    targets.push(match[1].replace(/^<|>$/g, ""));
  }
  return targets;
}

async function validateLinks(files) {
  const markdownFiles = files.filter((file) => extname(file) === ".md");
  for (const file of markdownFiles) {
    const text = await readFile(file, "utf8");
    for (const rawTarget of markdownTargets(text)) {
      if (/^(?:[a-z]+:|#)/i.test(rawTarget)) continue;
      let target;
      try {
        target = decodeURIComponent(rawTarget.split("#", 1)[0]);
      } catch {
        errors.push(`${display(file)}: invalid URL encoding in '${rawTarget}'`);
        continue;
      }
      if (!target) continue;
      const absolute = target.startsWith("/")
        ? join(repositoryRoot, target)
        : resolve(dirname(file), target);
      try {
        await stat(absolute);
      } catch {
        errors.push(`${display(file)}: broken local link '${rawTarget}'`);
      }
    }
  }
  return markdownFiles.length;
}

for (const bucket of allowedBuckets) {
  try {
    const bucketStat = await stat(join(skillsRoot, bucket));
    if (!bucketStat.isDirectory()) throw new Error("not a directory");
  } catch {
    errors.push(`skills/${bucket}/: missing lifecycle bucket`);
  }
}

const files = await filesBelow(repositoryRoot);
const skillCount = await validateSkills(files);
const markdownCount = await validateLinks(files);

if (errors.length > 0) {
  console.error(`Skill validation failed with ${errors.length} error(s):`);
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(
  `Validated ${skillCount} skill(s), ${allowedBuckets.size} lifecycle buckets, and ${markdownCount} Markdown file(s).`,
);
