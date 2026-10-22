#!/usr/bin/env node
// Measure complete helper processes against synthetic local configuration.
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { parseArgs, isDeepStrictEqual } from 'node:util';

const { values } = parseArgs({ options: {
  samples: { type: 'string', default: '30' },
  'python-baseline': { type: 'string' },
} });
const samples = Number(values.samples);
if (!Number.isSafeInteger(samples) || samples < 1) throw new Error('samples must be a positive integer');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const helper = join(root, 'skills/engineering/gh-issue/scripts/project-workflow.cjs');
const directory = mkdtempSync(join(tmpdir(), 'gh-issue-benchmark-'));
const config = join(directory, 'config.json');
const environment = { ...process.env, AGENT_SKILLS_CONFIG: config, AGENT_SKILLS_PROJECT_OVERRIDE: '{}' };
const commands = { node: [process.execPath, helper] };
if (values['python-baseline']) commands.python = ['python3', resolve(values['python-baseline'])];
const large = { organizations: {}, repositories: {} };
for (let organization = 0; organization < 20; organization++) {
  const owner = 'org' + organization;
  const boards = {};
  for (let board = 1; board <= 10; board++) {
    boards[owner + '/' + board] = { fields: { Status: { start: 'In progress', complete: 'Done' } } };
  }
  large.organizations[owner] = { projectSync: { boards } };
  for (let repository = 0; repository < 10; repository++) {
    large.repositories[owner + '/repo' + repository] = { taskBaseBranch: 'main' };
  }
}
const cases = [
  { name: 'empty-config', config: {}, args: ['resolve', 'org0/repo0', '--start-settings'] },
  { name: 'tiered-config', config: large, args: ['resolve', 'org0/repo0', '--start-settings'] },
  { name: 'disabled-transition', config: { projectSync: { enabled: false } },
    args: ['transition', 'start', 'org0/repo0', '1'] },
];
function measure(command, args) {
  const before = performance.now();
  const result = spawnSync(command[0], [...command.slice(1), ...args], {
    env: environment, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
  });
  const elapsed = performance.now() - before;
  if (result.error || result.status !== 0) throw new Error(result.stderr || result.stdout || result.error.message);
  return { elapsed, output: JSON.parse(result.stdout) };
}
try {
  const results = [];
  for (const fixture of cases) {
    writeFileSync(config, JSON.stringify(fixture.config));
    const measurements = Object.fromEntries(Object.keys(commands).map(name => [name, []]));
    const expected = measure(commands.node, fixture.args).output;
    for (const command of Object.values(commands)) {
      if (!isDeepStrictEqual(measure(command, fixture.args).output, expected)) {
        throw new Error('Runtime outputs differ for ' + fixture.name);
      }
    }
    // Warm file caches. Every timed sample still starts a new runtime process.
    for (let warmup = 0; warmup < 3; warmup++) {
      for (const command of Object.values(commands)) measure(command, fixture.args);
    }
    const entries = Object.entries(commands);
    for (let sample = 0; sample < samples; sample++) {
      // Alternate execution order to reduce bias from machine load over time.
      for (const [name, command] of sample % 2 ? [...entries].reverse() : entries) {
        const { elapsed } = measure(command, fixture.args);
        measurements[name].push(elapsed);
      }
    }
    for (const [runtime, durations] of Object.entries(measurements)) {
      durations.sort((a, b) => a - b);
      const middle = Math.floor(samples / 2);
      results.push({ case: fixture.name, runtime, samples,
        medianMs: Number((samples % 2 ? durations[middle] : (durations[middle - 1] + durations[middle]) / 2).toFixed(2)),
        p95Ms: Number(durations[Math.ceil(samples * 0.95) - 1].toFixed(2)) });
    }
  }
  console.log(JSON.stringify({
    nodeVersion: process.version, platform: process.platform, architecture: process.arch,
    ...(values['python-baseline'] ? { pythonVersion: spawnSync('python3', ['--version'], { encoding: 'utf8' }).stdout.trim() } : {}),
    scope: 'Process startup and local configuration only. No GitHub calls or workspace operations.',
    tieredFixture: { organizations: Object.keys(large.organizations).length,
      repositories: Object.keys(large.repositories).length },
    results,
  }, null, 2));
} finally {
  rmSync(directory, { recursive: true, force: true });
}
