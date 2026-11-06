#!/usr/bin/env node
// Configuration and assigned-board lifecycle operations. Node built-ins only.
const fs = require('node:fs');
const path = require('node:path');
const { homedir } = require('node:os');
const { parseArgs } = require('node:util');
const HERE = __dirname;
const DEFAULTS = {
  worktreeRoot: null, worktreePath: null, taskBaseBranch: null, branchKey: null,
  integrationBranchTemplate: 'integration/issue-{number}-{slug}',
  taskBranchTemplate: 'feat/issue-{number}-{slug}',
  worktreeTemplate: 'issue-{number}-{slug}',
  projectSync: { enabled: true, ancestors: true, boards: {} },
};
// A workspace file documents layout rules for every member of a shared workspace.
const WORKSPACE_FILE = '.gh-issue.json';
const WORKSPACE_SETTINGS = ['worktreePath', 'taskBranchTemplate', 'integrationBranchTemplate', 'branchKey', 'taskBaseBranch'];
const BRANCH_VARIABLES = ['number', 'slug', 'key'];
const TEMPLATE_VARIABLES = {
  taskBranchTemplate: BRANCH_VARIABLES,
  integrationBranchTemplate: BRANCH_VARIABLES,
  worktreeTemplate: BRANCH_VARIABLES,
  worktreePath: ['root', 'workspace', 'owner', 'repo', 'checkout', 'branch', 'number', 'slug', 'key'],
};
const PLACEHOLDER = /\{([a-z]+)\}/g;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.hasOwn(value, key);
const nonempty = value => typeof value === 'string' && value.trim().length > 0;
// Expand Unicode case variants such as ß/SS and final sigma. Dotless ı stays distinct.
const fold = value => value.toLowerCase().replace(/[^\x00-\x7f]/gu,
  character => character === '\u0131' ? character : character.toUpperCase().toLowerCase());
const clone = value => JSON.parse(JSON.stringify(value));
const unknown = (value, allowed) => Object.keys(value).some(key => !allowed.includes(key));

class Problem extends Error {
  constructor(message, status = 'blocked', details = {}) {
    super(message);
    this.result = { status, message, ...details };
  }
}

function emit(value) {
  process.stdout.write(JSON.stringify(value, null, 2) + '\n');
}

function run(command, ...args) {
  const { spawnSync } = require('node:child_process');
  // Preserve argument boundaries: configuration and GitHub data never enter a shell.
  const result = spawnSync(command, args, { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  if (result.error || result.status !== 0) {
    throw new Problem(result.stderr?.trim() || result.stdout?.trim() ||
      result.error?.message || 'Command failed: ' + command);
  }
  return result.stdout;
}

function jsonObject(text) {
  const value = JSON.parse(text);
  if (!object(value)) throw new Problem('Configuration must be a JSON object');
  return value;
}

// Keep the GitHub spelling for rendered paths. Configuration keys use the folded form.
function repositoryDisplayName(value) {
  if (value === '.') {
    value = run('git', 'config', '--get', 'remote.origin.url').trim()
      .replace(/^(git@github.com:|https:\/\/github.com\/|ssh:\/\/git@github.com\/)/i, '')
      .replace(/\.git$/i, '');
  }
  if (!/^[\w.-]+\/[\w.-]+$/.test(value)) throw new Problem('Expected OWNER/REPOSITORY');
  return value;
}

function repositoryName(value) {
  return fold(repositoryDisplayName(value));
}

function keyed(value, kind) {
  if (!object(value)) throw new Problem(kind + ' must be an object');
  const result = Object.create(null);
  for (const [key, item] of Object.entries(value)) {
    const normalized = key.startsWith('id:') ? key : fold(key);
    if (own(result, normalized)) throw new Problem('Ambiguous case-insensitive ' + kind + ': ' + key);
    result[normalized] = item;
  }
  return result;
}

function layer(value) {
  if (!object(value)) throw new Problem('Each configuration tier must be an object');
  const result = clone(value);
  // Ignore the retired manager setting at every configuration tier.
  delete result.worktreeManager;
  if (!own(result, 'projectSync')) return result;
  const sync = result.projectSync;
  if (!object(sync)) throw new Problem('projectSync must be an object');
  if (unknown(sync, ['enabled', 'ancestors', 'boards'])) throw new Problem('Unknown projectSync setting');
  for (const flag of ['enabled', 'ancestors']) {
    if (own(sync, flag) && typeof sync[flag] !== 'boolean') {
      throw new Problem('projectSync.' + flag + ' must be boolean');
    }
  }
  const boards = keyed(own(sync, 'boards') ? sync.boards : {}, 'boards');
  for (const [identity, board] of Object.entries(boards)) {
    if (!/^[\w.-]+\/[1-9][0-9]*$/.test(identity) || !object(board)) {
      throw new Problem('Board keys must be OWNER/NUMBER with object values');
    }
    if (unknown(board, ['enabled', 'fields'])) throw new Problem('Unknown board setting: ' + identity);
    if (own(board, 'enabled') && typeof board.enabled !== 'boolean') {
      throw new Problem('Board enabled must be boolean');
    }
    const fields = keyed(own(board, 'fields') ? board.fields : {}, 'fields');
    for (const [field, events] of Object.entries(fields)) {
      if (!field || !object(events) || unknown(events, ['start', 'complete', 'fieldId'])) {
        throw new Problem('Fields map to start and complete options, with an optional exact fieldId');
      }
      if (!Object.values(events).every(nonempty)) {
        throw new Problem('Transition values must be nonempty strings');
      }
    }
    board.fields = fields;
  }
  sync.boards = boards;
  return result;
}

function overlay(base, update, sources = null, source = '', prefix = '') {
  // Copy only modified paths. Callers treat unmodified nested values as immutable.
  const result = Object.assign(Object.create(null), object(base) ? base : {});
  for (const [key, value] of Object.entries(update)) {
    const location = (prefix ? prefix + '.' : '') + key;
    if (object(value)) {
      // A replaced scalar default, such as a null branchKey, no longer has its own source.
      if (sources) delete sources[location];
      result[key] = overlay(result[key], value, sources, source, location);
    } else {
      result[key] = value;
      if (sources) {
        // A scalar that replaces an object also replaces the sources of its fields.
        for (const field of Object.keys(sources)) {
          if (field.startsWith(location + '.')) delete sources[field];
        }
        sources[location] = source;
      }
    }
  }
  return result;
}

function legacyLayer(setting) {
  if (!object(setting)) throw new Problem('Legacy projectStatus must be an object');
  const enabled = own(setting, 'enabled') ? setting.enabled : false;
  if (typeof enabled !== 'boolean') throw new Problem('Legacy projectStatus.enabled must be boolean');
  if (!enabled) return { projectSync: { enabled: false } };
  const { owner, number } = setting;
  if (!owner && !number) return { projectSync: { enabled: true, boards: {} } };
  if (!nonempty(owner) || !Number.isSafeInteger(number) || number <= 0) {
    throw new Problem('Legacy projectStatus requires owner and a positive integer number together');
  }
  const field = own(setting, 'field') ? setting.field : 'Status';
  const option = own(setting, 'startOption') ? setting.startOption : 'In Progress';
  if (![field, option].every(nonempty)) throw new Problem('Legacy field and startOption must be nonempty strings');
  return { projectSync: { enabled: true, boards: {
    [fold(owner) + '/' + number]: { enabled: true, fields: { [field]: { start: option } } },
  } } };
}

function migrate(raw) {
  let value = clone(raw);
  const version = own(value, 'schemaVersion') ? value.schemaVersion : 1;
  if (![1, 2].includes(version)) throw new Problem('Unsupported configuration schemaVersion');
  const orgs = keyed(own(value, 'organizations') ? value.organizations : {}, 'organizations');
  const repos = keyed(own(value, 'repositories') ? value.repositories : {}, 'repositories');
  if (Object.keys(orgs).some(key => !/^[\w.-]+$/.test(key))) {
    throw new Problem('Organization keys must be repository owners');
  }
  if (Object.keys(repos).some(key => !/^[\w.-]+\/[\w.-]+$/.test(key))) {
    throw new Problem('Repository keys must be OWNER/REPOSITORY');
  }
  const shared = value.projectStatus;
  delete value.projectStatus;
  if (shared != null) {
    if (!object(shared)) throw new Problem('Legacy projectStatus must be an object');
    const converted = legacyLayer(shared);
    if (shared.enabled) {
      if (!shared.owner) throw new Problem('Enabled legacy shared projectStatus requires an owner and number');
      const owner = fold(shared.owner);
      orgs[owner] = overlay(converted, orgs[owner] ?? {});
    } else {
      value = overlay(converted, value);
    }
  }
  for (const [repo, original] of Object.entries(repos)) {
    if (!object(original)) throw new Problem('Repository settings must be an object');
    let settings = original;
    const old = settings.projectStatus;
    delete settings.projectStatus;
    if (old != null) {
      if (!object(old)) throw new Problem('Legacy repository projectStatus must be an object');
      const base = shared && fold(String(shared.owner ?? '')) === repo.split('/')[0] ? shared : {};
      const converted = legacyLayer(overlay(base, old));
      if (base.enabled && converted.projectSync.enabled) {
        const previous = Object.keys(legacyLayer(base).projectSync.boards)[0];
        if (!own(converted.projectSync.boards, previous)) converted.projectSync.boards[previous] = { enabled: false };
      }
      settings = overlay(converted, settings);
    }
    repos[repo] = layer(settings);
  }
  value.organizations = Object.fromEntries(Object.entries(orgs).map(([key, item]) => [key, layer(item)]));
  value.repositories = repos;
  value.schemaVersion = 2;
  return layer(value);
}

function resolver(raw, override, workspace = null, { layout = true } = {}) {
  // Normalize once per invocation, even when several ancestors share a repository.
  const normalized = migrate(raw);
  const invocation = layer(override);
  const global = Object.fromEntries(Object.entries(normalized)
    .filter(([key]) => !['organizations', 'repositories', 'schemaVersion'].includes(key)));
  const cache = new Map();
  return repository => {
    if (cache.has(repository)) return cache.get(repository);
    const owner = repository.split('/')[0];
    const sources = Object.create(null);
    let effective = overlay({}, DEFAULTS, sources, 'default');
    const tiers = [
      ['global', global],
      ['organization:' + owner, own(normalized.organizations, owner) ? normalized.organizations[owner] : {}],
      ...(workspace ? [['workspace:' + workspace.file, workspace.settings]] : []),
      ['repository:' + repository, own(normalized.repositories, repository) ? normalized.repositories[repository] : {}],
      ['invocation', invocation],
    ];
    for (const [source, values] of tiers) effective = overlay(effective, values, sources, source);
    for (const [identity, board] of Object.entries(effective.projectSync.boards)) {
      if (!own(board, 'enabled')) {
        effective.projectSync.boards[identity] = { ...board, enabled: true };
        sources['projectSync.boards.' + identity + '.enabled'] = 'default';
      }
    }
    // Board transitions read no layout settings and have no workspace file.
    if (layout) validateLayout(effective, sources);
    const result = { status: 'resolved', repository, effective, sources };
    cache.set(repository, result);
    return result;
  };
}

function placeholders(template) {
  return [...template.matchAll(PLACEHOLDER)].map(match => match[1]);
}

function validateLayout(effective, sources) {
  if (effective.worktreeRoot !== null &&
      (typeof effective.worktreeRoot !== 'string' || !path.isAbsolute(effective.worktreeRoot))) {
    throw new Problem('worktreeRoot must be an absolute path');
  }
  if (effective.taskBaseBranch !== null && !nonempty(effective.taskBaseBranch)) {
    throw new Problem('taskBaseBranch must be a nonempty branch name');
  }
  if (effective.branchKey !== null) keyExpression(effective.branchKey);
  for (const [name, allowed] of Object.entries(TEMPLATE_VARIABLES)) {
    const template = effective[name];
    if (name === 'worktreePath' && template === null) continue;
    if (!nonempty(template)) throw new Problem(name + ' must be a nonempty string');
    for (const variable of placeholders(template)) {
      // Only the workspace file knows its own folder.
      if (variable === 'workspace' && allowed.includes(variable) &&
          !String(sources[name]).startsWith('workspace:')) {
        throw new Problem(name + ' uses {workspace}, but ' + WORKSPACE_FILE + ' did not supply ' + name);
      }
      if (!allowed.includes(variable)) {
        throw new Problem(name + ' cannot use {' + variable + '}; allowed variables: ' +
          allowed.map(item => '{' + item + '}').join(', '));
      }
      if (variable === 'key' && effective.branchKey === null) {
        throw new Problem(name + ' uses {key}, which requires branchKey');
      }
    }
  }
}

function keyExpression(branchKey) {
  if (!object(branchKey) || unknown(branchKey, ['from', 'pattern'])) {
    throw new Problem('branchKey must be an object with from and pattern');
  }
  if (branchKey.from !== 'titlePrefix') throw new Problem('branchKey.from must be titlePrefix');
  if (!nonempty(branchKey.pattern)) throw new Problem('branchKey.pattern must be a nonempty regular expression');
  let expression;
  try {
    expression = new RegExp(branchKey.pattern);
  } catch (error) {
    throw new Problem('branchKey.pattern is not a valid regular expression: ' + error.message);
  }
  // An empty alternative always matches, so the result length counts the capture groups.
  if (new RegExp(branchKey.pattern + '|').exec('').length !== 2) {
    throw new Problem('branchKey.pattern must contain exactly one capture group');
  }
  return expression;
}

function findWorkspace(checkout) {
  if (!checkout) return null;
  const real = location => {
    try {
      return fs.realpathSync(location);
    } catch {
      return null;
    }
  };
  const home = real(homedir());
  // Search the primary checkout folder and each parent, through the home directory.
  for (let folder = path.resolve(checkout); ; folder = path.dirname(folder)) {
    const file = path.join(folder, WORKSPACE_FILE);
    let text = null;
    try {
      text = fs.readFileSync(file, 'utf8');
    } catch (error) {
      if (!['ENOENT', 'ENOTDIR'].includes(error.code)) throw new Problem('Cannot read ' + file + ': ' + error.message);
    }
    if (text !== null) return { file, folder, settings: workspaceSettings(text, file) };
    if (path.dirname(folder) === folder || (home !== null && real(folder) === home)) return null;
  }
}

function workspaceSettings(text, file) {
  let value;
  try {
    value = JSON.parse(text);
  } catch (error) {
    throw new Problem(file + ' is not valid JSON: ' + error.message);
  }
  if (!object(value)) throw new Problem(file + ' must contain a JSON object');
  for (const key of Object.keys(value)) {
    if (WORKSPACE_SETTINGS.includes(key)) continue;
    if (key === 'worktreeRoot') {
      throw new Problem(file + ' cannot contain worktreeRoot, which is specific to one machine; set it in ' + configPath());
    }
    if (['projectSync', 'projectStatus'].includes(key)) {
      throw new Problem(file + ' cannot contain board mappings (' + key + '); set them with the config workflow');
    }
    throw new Problem(file + ' cannot contain ' + key + '; it accepts only ' + WORKSPACE_SETTINGS.join(', '));
  }
  return value;
}

// Use the primary checkout of the current directory when it belongs to the repository.
function currentCheckout(repository) {
  try {
    if (repositoryName('.') !== repository) return null;
    return /^worktree (.+)$/m.exec(run('git', 'worktree', 'list', '--porcelain'))?.[1] ?? null;
  } catch {
    return null;
  }
}

function configPath() {
  const value = process.env.AGENT_SKILLS_CONFIG ?? path.join(homedir(), '.config/agent-skills/config.json');
  return value === '~' ? homedir() : value.startsWith('~/') ? path.join(homedir(), value.slice(2)) : value;
}

function loadConfig(filename) {
  let bytes;
  try {
    bytes = fs.readFileSync(filename);
  } catch (error) {
    if (error.code === 'ENOENT') return [Buffer.alloc(0), {}];
    throw error;
  }
  return [bytes, jsonObject(bytes.toString('utf8'))];
}

function connection(value, label) {
  if (!object(value) || !Array.isArray(value.nodes) || !Number.isSafeInteger(value.totalCount) ||
      value.totalCount !== value.nodes.length) throw new Problem('Incomplete GitHub ' + label);
  return value.nodes;
}

function readIssue(repository, number) {
  const response = JSON.parse(run(path.join(HERE, 'query.sh'), 'project-status', repository, String(number)));
  if (response.errors?.length) throw new Problem('GitHub returned errors', 'blocked', { errors: response.errors });
  const issue = response.data?.repository?.issue;
  if (!issue) throw new Problem('Issue was not found or is inaccessible');
  if (issue.number !== number || !['OPEN', 'CLOSED'].includes(issue.state)) {
    throw new Problem('Incomplete or unexpected GitHub issue identity');
  }
  return issue;
}

function issueRepository(issue) {
  if (issue.repository?.nameWithOwner) return repositoryName(issue.repository.nameWithOwner);
  const match = /^https:\/\/github.com\/([^/]+\/[^/]+)\/issues\/[0-9]+$/i.exec(issue.url ?? '');
  if (!match) throw new Problem('Incomplete GitHub issue identity');
  return repositoryName(match[1]);
}

function choose(selector, objects, kind) {
  if (!Array.isArray(objects) || objects.some(item => !object(item))) {
    throw new Problem('Incomplete GitHub ' + kind);
  }
  const matches = objects.filter(item => selector.startsWith('id:')
    ? item.id === selector.slice(3) : fold(item.name ?? '') === fold(selector));
  if (matches.length !== 1) {
    throw new Problem('Expected one ' + kind + ' matching ' + selector, 'needs_input', {
      candidates: (matches.length ? matches : objects).map(item => ({ id: item.id ?? null, name: item.name ?? null })),
    });
  }
  if (!matches[0].id) throw new Problem('Missing GitHub ID for ' + kind);
  return matches[0];
}

function boardInventory(issue, sync) {
  const seen = new Set();
  return connection(issue.projectItems, 'board memberships').map(item => {
    const project = item?.project;
    const owner = project?.owner?.login;
    if (!nonempty(owner) || !Number.isSafeInteger(project.number) || !project.id || !item.id) {
      throw new Problem('Inaccessible or incomplete assigned board');
    }
    const identity = fold(owner) + '/' + project.number;
    if (seen.has(identity)) throw new Problem('Duplicate assigned board ' + identity);
    seen.add(identity);
    const fields = connection(project.fields, 'board fields');
    if (fields.some(field => !object(field))) throw new Problem('Incomplete GitHub board fields');
    return {
      identity, title: project.title ?? null, projectId: project.id, itemId: item.id,
      fields: fields.filter(field => own(field, 'options')),
      values: connection(item.fieldValues, 'board field values'), mapping: sync.boards[identity] ?? null,
    };
  });
}

function planIssue(issue, sync, event) {
  const boards = boardInventory(issue, sync);
  const updates = [], unresolved = [];
  const identity = { repository: issueRepository(issue), issue: issue.number };
  for (const board of boards) {
    const mapping = board.mapping;
    if (!sync.enabled || (mapping !== null && !mapping.enabled)) {
      board.management = 'unmanaged';
      continue;
    }
    if (mapping === null || !Object.keys(mapping.fields ?? {}).length) {
      board.management = 'unconfigured';
      unresolved.push({ ...identity, board: board.identity, reason: 'Select fields or leave this board unmanaged' });
      continue;
    }
    board.management = 'managed';
    const seenFields = new Set();
    for (const [selector, events] of Object.entries(mapping.fields)) {
      const field = choose(own(events, 'fieldId') ? 'id:' + events.fieldId : selector,
        board.fields, 'field on ' + board.identity);
      if (seenFields.has(field.id)) throw new Problem('Multiple mappings select the same field on ' + board.identity);
      seenFields.add(field.id);
      for (const currentEvent of event === 'config' ? ['start', 'complete'] : [event]) {
        if (!own(events, currentEvent)) {
          unresolved.push({ ...identity, board: board.identity, field: field.name, event: currentEvent,
            reason: 'Select a transition option' });
          continue;
        }
        const option = choose(events[currentEvent], field.options, 'option for ' + field.name);
        const existing = board.values.filter(value => value?.field?.id === field.id);
        if (existing.length > 1) throw new Problem('Duplicate current field value on ' + board.identity);
        const current = existing[0] ?? {};
        updates.push({ ...identity, board: board.identity, projectId: board.projectId, itemId: board.itemId,
          fieldId: field.id, field: field.name, optionId: option.id, expected: option.name,
          current: current.name ?? null, event: currentEvent,
          status: current.optionId === option.id ? 'unchanged' : 'pending' });
      }
    }
  }
  return { boards, updates, unresolved };
}

function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (object(value)) return '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
  return JSON.stringify(value);
}

function saveConfig(filename, rawBytes, proposal) {
  const { randomBytes } = require('node:crypto');
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  const lock = filename + '.lock';
  try {
    fs.mkdirSync(lock);
  } catch (error) {
    if (error.code === 'EEXIST') throw new Problem('Another configuration write holds ' + lock);
    throw error;
  }
  let temporary;
  try {
    const unchanged = () => {
      if (!loadConfig(filename)[0].equals(rawBytes)) {
        throw new Problem('Configuration changed; review a fresh preview', 'stale_preview');
      }
    };
    unchanged();
    const candidate = filename + '.' + randomBytes(12).toString('hex');
    const descriptor = fs.openSync(candidate, 'wx', 0o600);
    temporary = candidate;
    try {
      fs.writeFileSync(descriptor, JSON.stringify(proposal, null, 2) + '\n');
      fs.fsyncSync(descriptor);
      if (fs.existsSync(filename)) fs.fchmodSync(descriptor, fs.statSync(filename).mode & 0o777);
    } finally {
      fs.closeSync(descriptor);
    }
    unchanged();
    fs.renameSync(temporary, filename);
    temporary = undefined;
  } finally {
    try {
      if (temporary) fs.unlinkSync(temporary);
    } finally {
      fs.rmdirSync(lock);
    }
  }
}

function configCommand(args, rawBytes, raw, repository, override, workspace) {
  const filename = configPath();
  let proposal = migrate(raw);
  const patch = own(args, 'set') ? layer(jsonObject(args.set)) : null;
  if (own(args, 'confirm') && patch === null) throw new Problem('--confirm requires the same --set patch as the preview');
  if (patch !== null) {
    if (unknown(patch, Object.keys(DEFAULTS))) {
      throw new Problem('The patch may contain only workflow settings for the selected scope');
    }
    if (Object.keys(override).length) {
      throw new Problem('Use --override for invocation-only resolution, not a saved configuration patch');
    }
    if (args.scope === 'global') {
      proposal = overlay(proposal, patch);
    } else {
      const [group, key] = args.scope === 'organization'
        ? ['organizations', repository.split('/')[0]] : ['repositories', repository];
      proposal[group] = overlay(proposal[group], {
        [key]: overlay(own(proposal[group], key) ? proposal[group][key] : {}, patch),
      });
    }
  }
  const resolved = resolver(proposal, override, workspace)(repository);
  // The workspace file is a read-only source. Config never writes it.
  resolved.workspace = workspace ? { file: workspace.file, folder: workspace.folder } : null;
  let boards = [], unresolved = [];
  if (args.issue) {
    const issue = readIssue(repository, args.issue);
    if (issueRepository(issue) !== repository) throw new Problem('GitHub returned an issue from another repository');
    ({ boards, unresolved } = planIssue(issue, resolved.effective.projectSync, 'config'));
  }
  const changedBoards = patch?.projectSync?.boards ?? {};
  if (Object.keys(changedBoards).length && !args.issue) {
    throw new Problem('Board configuration requires --issue for assigned-board discovery');
  }
  for (const identity of Object.keys(changedBoards)) {
    if (!boards.some(board => board.identity === identity)) {
      throw new Problem('Board ' + identity + ' is not assigned to the issue');
    }
  }
  const result = { ...resolved, boards, unresolved };
  if (patch === null) {
    result.status = unresolved.length ? 'needs_input' : args.issue ? 'configured' : 'resolved';
    if (unresolved.length) result.message = 'Use config to select mappings or leave assigned boards unmanaged';
    emit(result);
    return unresolved.length ? 2 : 0;
  }
  if (unresolved.some(item => own(changedBoards, item.board))) {
    throw new Problem('Selected board mappings need explicit fields and transition values', 'needs_input', { unresolved });
  }
  const { createHash } = require('node:crypto');
  const token = createHash('sha256').update(rawBytes)
    .update(canonical({ repository, scope: args.scope, proposal, boards })).digest('hex');
  const preview = { ...result, status: 'preview', token, scope: args.scope,
    configuration: proposal, path: filename, before: raw };
  if (!own(args, 'confirm')) {
    emit(preview);
    return 0;
  }
  if (args.confirm !== token) {
    throw new Problem('Configuration or assigned-board discovery changed; review a fresh preview', 'stale_preview', { preview });
  }
  saveConfig(filename, rawBytes, proposal);
  emit({ ...result, status: 'saved', scope: args.scope, path: filename });
  return 0;
}

// Match the historical shell slug: ASCII lowercase, other runs become one hyphen.
function slugify(title) {
  const slug = title.replace(/[A-Z]/g, character => character.toLowerCase())
    .replace(/[^a-z0-9]+/g, '-').replace(/^-/, '').replace(/-$/, '')
    .slice(0, 48).replace(/-$/, '');
  return slug || 'work';
}

function issueKey(effective, title) {
  if (effective.branchKey === null) return { key: null, text: null };
  const text = keyExpression(effective.branchKey).exec(title)?.[1];
  return text ? { key: text.toLowerCase(), text } : { key: null, text: null };
}

// Substitute in one pass so that a value never introduces another variable.
function render(template, values) {
  return template.replace(PLACEHOLDER, (whole, name) => own(values, name) ? String(values[name]) : whole);
}

function templatePattern(template, number) {
  const escape = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  let source = '', last = 0;
  for (const match of template.matchAll(PLACEHOLDER)) {
    source += escape(template.slice(last, match.index)) + (match[1] === 'number' ? String(number) : '.+');
    last = match.index + match[0].length;
  }
  return new RegExp('^' + source + escape(template.slice(last)) + '$');
}

const sortedUnique = values => [...new Set(values)].sort();

// Decide which branch names belong to one issue. Start, status, finish, clean,
// and cancel share this rule. A link is the proof of ownership. Without a link,
// a name match counts only when no evidence gives the branch to another issue.
// `records` maps a branch to the issue that start recorded for it in this clone.
function discover(effective, issue, names, records) {
  const template = issue.compound ? effective.integrationBranchTemplate : effective.taskBranchTemplate;
  const variables = placeholders(template);
  const { key } = issueKey(effective, issue.title);
  const slug = slugify(issue.title);
  const missingKey = variables.includes('key') && key === null;
  const rendered = missingKey ? null : render(template, { number: issue.number, slug, key });
  const result = { number: issue.number, template, key, rendered, missingKey };
  const linked = sortedUnique(issue.linked);
  if (linked.length) {
    return { ...result, source: 'linked', matches: linked, possible: [], unverified: [], claimed: [] };
  }
  const recorded = name => own(records, name) ? records[name] : null;
  const elsewhere = name => recorded(name) !== null && recorded(name) !== issue.number;
  const pattern = variables.includes('number') ? templatePattern(template, issue.number) : null;
  const fits = sortedUnique(names.filter(name => pattern ? pattern.test(name) : name === rendered));
  // Every issue with the same key renders a name without {number}, so only the
  // record of this issue proves that such a name belongs to it.
  const unverified = pattern ? [] : fits.filter(name => recorded(name) === null);
  const matches = fits.filter(name => !elsewhere(name) && !unverified.includes(name));
  const claimed = fits.filter(elsewhere).map(branch => ({ branch, issue: recorded(branch) }));
  // The historical number rule now identifies only possible branches for a question.
  const numberRule = new RegExp('(^|[-_/])' + issue.number + '([-_/]|$)');
  const possible = sortedUnique(names.filter(name => numberRule.test(name) && !fits.includes(name) && !elsewhere(name)));
  return { ...result, source: matches.length ? 'template' : 'none', matches, possible, unverified, claimed };
}

// Read the issue that start recorded for each branch in this clone.
function branchRecords(checkout) {
  const records = Object.create(null);
  if (!checkout) return records;
  const { spawnSync } = require('node:child_process');
  const result = spawnSync('git', ['-C', checkout, 'config', '--get-regexp', '^branch\\..*\\.gh-issue$'],
    { encoding: 'utf8' });
  // Git exits with 1 when no key matches.
  if (result.status === 1) return records;
  if (result.error || result.status !== 0) {
    throw new Problem('Cannot read the branch records of ' + checkout + ': ' + (result.stderr || result.error?.message || '').trim());
  }
  for (const line of result.stdout.split('\n')) {
    const match = /^branch\.(.+)\.gh-issue ([1-9][0-9]*)$/.exec(line);
    if (match) records[match[1]] = Number(match[2]);
  }
  return records;
}

function branchesCommand(effective, workspace, checkout) {
  let input;
  try {
    input = JSON.parse(fs.readFileSync(0, 'utf8'));
  } catch (error) {
    throw new Problem('Branch discovery expects JSON input: ' + error.message);
  }
  const strings = value => Array.isArray(value) && value.every(item => typeof item === 'string');
  if (!object(input) || !strings(input.names) || !Array.isArray(input.issues)) {
    throw new Problem('Branch discovery expects names and issues');
  }
  const records = branchRecords(checkout);
  const issues = input.issues.map(issue => {
    if (!object(issue) || !Number.isSafeInteger(issue.number) || typeof issue.title !== 'string' ||
        typeof issue.compound !== 'boolean' || !strings(issue.linked)) {
      throw new Problem('Each issue needs number, title, compound, and linked');
    }
    return discover(effective, issue, input.names, records);
  });
  emit({ status: 'resolved', workspace: workspace?.file ?? null, records: { ...records }, issues });
  return 0;
}

function pathCommand(args, displayName, effective, sources, workspace) {
  for (const name of ['checkout', 'number', 'title', 'branch']) {
    if (!own(args, name)) throw new Problem('Worktree path rendering requires --' + name);
  }
  const number = positiveInteger(args.number);
  const checkout = path.resolve(args.checkout);
  const [owner, repo] = displayName.split('/');
  const { key } = issueKey(effective, args.title);
  const values = {
    root: effective.worktreeRoot ?? path.join(path.dirname(path.dirname(checkout)), 'worktrees'),
    workspace: workspace?.folder, owner, repo, checkout: path.basename(checkout), branch: args.branch,
    number, slug: slugify(args.title), key,
  };
  const [setting, template] = effective.worktreePath !== null
    ? ['worktreePath', effective.worktreePath]
    : ['worktreeTemplate', '{root}/{repo}/' + effective.worktreeTemplate];
  const variables = placeholders(template);
  if (variables.includes('key') && key === null) {
    throw new Problem('The title of issue #' + number + ' does not match branchKey.pattern, so ' +
      setting + ' cannot render {key}. Which destination should issue #' + number + ' use?', 'needs_input');
  }
  for (const name of variables) {
    // Only the configured folders can climb the tree. Issue data cannot.
    if (!['root', 'workspace'].includes(name) && String(values[name]).split('/').some(part => ['', '.', '..'].includes(part))) {
      throw new Problem(setting + ' renders {' + name + '} as an unsafe path part: ' + values[name]);
    }
  }
  const rendered = render(template, values).replace(/\/{2,}/g, '/').replace(/(.)\/$/, '$1');
  if (!path.isAbsolute(rendered)) throw new Problem(setting + ' renders a path that is not absolute: ' + rendered);
  emit({ status: 'resolved', path: rendered, setting, source: sources[setting] });
  return 0;
}

function transitionCommand(args, repository, raw, override) {
  const resolve = resolver(raw, override, null, { layout: false });
  const sync = resolve(repository).effective.projectSync;
  if (!sync.enabled) {
    emit({ status: 'disabled', updates: [], boards: [], unresolved: [] });
    return 0;
  }
  const focused = readIssue(repository, args.number);
  if (issueRepository(focused) !== repository) throw new Problem('GitHub returned an issue from another repository');
  let event = args.event;
  if (event === 'status') {
    event = focused.state === 'CLOSED' && focused.stateReason === 'COMPLETED' ? 'complete' : 'start';
    if (focused.state === 'CLOSED' && event !== 'complete') {
      emit({ status: 'not_completed', updates: [], boards: [], unresolved: [] });
      return 0;
    }
  }
  if (event === 'complete' && !args.preflight &&
      (focused.state !== 'CLOSED' || focused.stateReason !== 'COMPLETED')) {
    throw new Problem('A completion transition requires a confirmed completed issue');
  }
  if (event === 'start' && focused.state !== 'OPEN') throw new Problem('A start transition requires an open issue');
  const issues = [focused];
  if (event === 'start' && args.event !== 'status' && sync.ancestors) {
    for (let parent = focused.parent; parent != null; parent = parent.parent) {
      if (!parent.url) throw new Problem('Incomplete GitHub ancestor hierarchy');
      if (parent.state === 'OPEN') issues.push(parent);
    }
  }
  const boards = [], updates = [], unresolved = [];
  for (const issue of issues) {
    const issueRepo = issueRepository(issue);
    const settings = resolve(issueRepo).effective.projectSync;
    if (!settings.enabled) continue;
    const plan = planIssue(issue, settings, event);
    boards.push(...plan.boards.map(board => ({ ...board, repository: issueRepo, issue: issue.number })));
    updates.push(...plan.updates);
    unresolved.push(...plan.unresolved);
  }
  const result = { status: unresolved.length ? 'needs_input' : 'planned', event, boards, updates, unresolved };
  if (unresolved.length) {
    result.message = 'Run config for the reported issues before this transition';
    emit(result);
    return 2;
  }
  if (args['dry-run'] || args.preflight || args.event === 'status') {
    emit(result);
    return 0;
  }
  for (const update of updates) {
    if (update.status === 'unchanged') continue;
    try {
      run('gh', 'project', 'item-edit', '--id', update.itemId, '--project-id', update.projectId,
        '--field-id', update.fieldId, '--single-select-option-id', update.optionId);
      update.status = 'updated';
    } catch (error) {
      update.status = 'failed';
      update.error = error.message;
      result.status = 'partial_failure';
      emit(result);
      return 2;
    }
  }
  result.status = 'applied';
  emit(result);
  return 0;
}

function positiveInteger(value) {
  if (typeof value !== 'string' || !/^[0-9]+$/.test(value) || !Number.isSafeInteger(Number(value)) || Number(value) <= 0) {
    throw new Problem('Issue number must be positive');
  }
  return Number(value);
}

function main() {
  const command = process.argv[2];
  if (!['config', 'resolve', 'transition', 'branches', 'path'].includes(command)) {
    throw new Problem('Expected config, resolve, transition, branches, or path command');
  }
  const options = {
    override: { type: 'string', default: process.env.AGENT_SKILLS_PROJECT_OVERRIDE ?? '{}' },
    ...(command === 'transition' ? {
      'dry-run': { type: 'boolean' }, preflight: { type: 'boolean' },
    } : command === 'branches' ? {
      checkout: { type: 'string' },
    } : command === 'path' ? {
      checkout: { type: 'string' }, number: { type: 'string' }, title: { type: 'string' }, branch: { type: 'string' },
    } : {
      'start-settings': { type: 'boolean' }, issue: { type: 'string' }, checkout: { type: 'string' },
      scope: { type: 'string', default: 'repository' }, set: { type: 'string' }, confirm: { type: 'string' },
    }),
  };
  const { values: args, positionals } = parseArgs({ args: process.argv.slice(3), options, allowPositionals: true });
  if (positionals.length !== (command === 'transition' ? 3 : 1)) {
    throw new Problem(command === 'transition' ? 'Expected EVENT OWNER/REPOSITORY ISSUE_NUMBER' : 'Expected OWNER/REPOSITORY');
  }
  const displayName = repositoryDisplayName(positionals[command === 'transition' ? 1 : 0]);
  const repository = fold(displayName);
  const override = jsonObject(args.override);
  const [rawBytes, raw] = loadConfig(configPath());
  if (command === 'transition') {
    [args.event, , args.number] = positionals;
    if (!['start', 'complete', 'status'].includes(args.event)) throw new Problem('Expected start, complete, or status event');
    args.number = positiveInteger(args.number);
    return transitionCommand(args, repository, raw, override);
  }
  // Layout settings can come from a workspace file above the primary checkout.
  const workspace = findWorkspace(args.checkout ?? (command === 'config' ? currentCheckout(repository) : null));
  if (command === 'branches' || command === 'path') {
    const { effective, sources } = resolver(raw, override, workspace)(repository);
    if (command === 'branches') return branchesCommand(effective, workspace, args.checkout);
    return pathCommand(args, displayName, effective, sources, workspace);
  }
  if (own(args, 'issue')) args.issue = positiveInteger(args.issue);
  if (!['global', 'organization', 'repository'].includes(args.scope)) throw new Problem('Unknown configuration scope');
  if (command === 'config') return configCommand(args, rawBytes, raw, repository, override, workspace);
  const result = resolver(raw, override, workspace)(repository);
  emit(args['start-settings'] ? result.effective : result);
  return 0;
}

try {
  process.exitCode = main();
} catch (error) {
  emit(error instanceof Problem ? error.result : { status: 'blocked', message: error.message });
  process.exitCode = 2;
}
