#!/usr/bin/env python3
"""Configuration and assigned-board lifecycle operations (stdlib only)."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
DEFAULTS = {
    'worktreeManager': 'auto', 'worktreeRoot': None, 'taskBaseBranch': None,
    'integrationBranchTemplate': 'integration/issue-{number}-{slug}',
    'taskBranchTemplate': 'feat/issue-{number}-{slug}',
    'worktreeTemplate': 'issue-{number}-{slug}',
    'projectSync': {'enabled': True, 'ancestors': True, 'boards': {}}
}


class Problem(Exception):
    def __init__(self, message, status='blocked', **details):
        self.result = dict(status=status, message=message, **details)
        super().__init__(message)


def emit(value):
    print(json.dumps(value, ensure_ascii=False, indent=2))


def run(*args):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        raise Problem(result.stderr.strip() or result.stdout.strip() or 'Command failed: ' + args[0])
    return result.stdout


def json_object(text):
    value = json.loads(text)
    if not isinstance(value, dict):
        raise Problem('Configuration must be a JSON object')
    return value


def repository_name(value):
    if value == '.':
        value = run('git', 'config', '--get', 'remote.origin.url').strip()
        value = re.sub(r'^(git@github.com:|https://github.com/|ssh://git@github.com/)', '', value)
        value = re.sub(r'\.git$', '', value)
    if not re.fullmatch(r'[\w.-]+/[\w.-]+', value):
        raise Problem('Expected OWNER/REPOSITORY')
    return value.casefold()


def keyed(value, kind):
    if not isinstance(value, dict):
        raise Problem(kind + ' must be an object')
    result = {}
    for key, item in value.items():
        normalized = key if key.startswith('id:') else key.casefold()
        if normalized in result:
            raise Problem('Ambiguous case-insensitive ' + kind + ': ' + key)
        result[normalized] = item
    return result


def layer(value):
    if not isinstance(value, dict):
        raise Problem('Each configuration tier must be an object')
    result = copy.deepcopy(value)
    if 'projectSync' in result:
        sync = result['projectSync']
        if not isinstance(sync, dict):
            raise Problem('projectSync must be an object')
        if set(sync) - {'enabled', 'ancestors', 'boards'}:
            raise Problem('Unknown projectSync setting')
        for flag in ('enabled', 'ancestors'):
            if flag in sync and not isinstance(sync[flag], bool):
                raise Problem('projectSync.' + flag + ' must be boolean')
        boards = keyed(sync.get('boards', {}), 'boards')
        for identity, board in boards.items():
            if not re.fullmatch(r'[\w.-]+/[1-9][0-9]*', identity) or not isinstance(board, dict):
                raise Problem('Board keys must be OWNER/NUMBER with object values')
            if set(board) - {'enabled', 'fields'}:
                raise Problem('Unknown board setting: ' + identity)
            if 'enabled' in board and not isinstance(board['enabled'], bool):
                raise Problem('Board enabled must be boolean')
            fields = keyed(board.get('fields', {}), 'fields')
            for field, events in fields.items():
                if not field or not isinstance(events, dict) or set(events) - {'start', 'complete', 'fieldId'}:
                    raise Problem('Fields map to start and complete options, with an optional exact fieldId')
                if any(not isinstance(v, str) or not v.strip() for v in events.values()):
                    raise Problem('Transition values must be nonempty strings')
            board['fields'] = fields
        sync['boards'] = boards
    return result


def overlay(base, update, sources=None, source='', path=''):
    result = copy.deepcopy(base) if isinstance(base, dict) else {}
    for key, value in update.items():
        location = (path + '.' if path else '') + key
        if isinstance(value, dict):
            result[key] = overlay(result.get(key, {}), value, sources, source, location)
        else:
            result[key] = copy.deepcopy(value)
            if sources is not None:
                sources[location] = source
    return result


def legacy_layer(setting):
    if not isinstance(setting, dict):
        raise Problem('Legacy projectStatus must be an object')
    if not isinstance(setting.get('enabled', False), bool):
        raise Problem('Legacy projectStatus.enabled must be boolean')
    if not setting.get('enabled', False):
        return {'projectSync': {'enabled': False}}
    owner, number = setting.get('owner'), setting.get('number')
    if not owner and not number:
        # No named board means no authority to update assigned boards automatically.
        return {'projectSync': {'enabled': True, 'boards': {}}}
    if not isinstance(owner, str) or not owner or type(number) is not int or number <= 0:
        raise Problem('Legacy projectStatus requires owner and a positive integer number together')
    field = setting.get('field', 'Status')
    option = setting.get('startOption', 'In Progress')
    if any(not isinstance(v, str) or not v.strip() for v in (field, option)):
        raise Problem('Legacy field and startOption must be nonempty strings')
    return {'projectSync': {'enabled': True, 'boards': {
        owner.casefold() + '/' + str(number): {'enabled': True, 'fields': {
            field: {'start': option}
        }}
    }}}


def migrate(raw):
    value = copy.deepcopy(raw)
    if type(value.get('schemaVersion', 1)) is not int or value.get('schemaVersion', 1) not in (1, 2):
        raise Problem('Unsupported configuration schemaVersion')
    orgs = keyed(value.get('organizations', {}), 'organizations')
    repos = keyed(value.get('repositories', {}), 'repositories')
    if any(not re.fullmatch(r'[\w.-]+', key) for key in orgs):
        raise Problem('Organization keys must be repository owners')
    if any(not re.fullmatch(r'[\w.-]+/[\w.-]+', key) for key in repos):
        raise Problem('Repository keys must be OWNER/REPOSITORY')
    shared = value.pop('projectStatus', None)
    if shared is not None:
        if not isinstance(shared, dict):
            raise Problem("Legacy projectStatus must be an object")
        if shared.get('enabled', False):
            converted = legacy_layer(shared)
            owner = shared.get('owner')
            if not owner:
                raise Problem('Enabled legacy shared projectStatus requires an owner and number')
            owner = owner.casefold()
            orgs[owner] = overlay(converted, orgs.get(owner, {}))
        else:
            value = overlay(legacy_layer(shared), value)
    for repo, settings in repos.items():
        if not isinstance(settings, dict):
            raise Problem('Repository settings must be an object')
        old = settings.pop('projectStatus', None)
        if old is not None:
            if not isinstance(old, dict):
                raise Problem('Legacy repository projectStatus must be an object')
            base = shared if shared and str(shared.get('owner', '')).casefold() == repo.split('/')[0] else {}
            converted = legacy_layer(overlay(base, old))
            if base and base.get('enabled') and converted['projectSync']['enabled']:
                previous = next(iter(legacy_layer(base)['projectSync']['boards']))
                boards = converted['projectSync']['boards']
                if previous not in boards:
                    boards[previous] = {'enabled': False}
            settings = overlay(converted, settings)
        repos[repo] = layer(settings)
    value['organizations'] = {key: layer(item) for key, item in orgs.items()}
    value['repositories'] = repos
    value['schemaVersion'] = 2
    return layer(value)


def resolve(raw, repository, override=None):
    normalized = migrate(raw)
    sources = {}
    effective = overlay({}, DEFAULTS, sources, 'default')
    tiers = [('global', {k: v for k, v in normalized.items() if k not in ('organizations', 'repositories', 'schemaVersion')}),
             ('organization:' + repository.split('/')[0], normalized['organizations'].get(repository.split('/')[0], {})),
             ('repository:' + repository, normalized['repositories'].get(repository, {})),
             ('invocation', layer(override or {}))]
    for source, values in tiers:
        effective = overlay(effective, values, sources, source)
    sync = effective['projectSync']
    for identity, board in sync['boards'].items():
        if 'enabled' not in board:
            board['enabled'] = True
            sources['projectSync.boards.' + identity + '.enabled'] = 'default'
    if effective['worktreeManager'] not in ('auto', 'git', 'supacode'):
        raise Problem('worktreeManager must be auto, git, or supacode')
    if effective['worktreeRoot'] is not None and (not isinstance(effective['worktreeRoot'], str) or not Path(effective['worktreeRoot']).is_absolute()):
        raise Problem('worktreeRoot must be an absolute path')
    if effective['taskBaseBranch'] is not None and (not isinstance(effective['taskBaseBranch'], str) or not effective['taskBaseBranch']):
        raise Problem('taskBaseBranch must be a nonempty branch name')
    for name in ('integrationBranchTemplate', 'taskBranchTemplate', 'worktreeTemplate'):
        template = effective[name]
        if not isinstance(template, str) or '{number}' not in template or '{slug}' not in template:
            raise Problem('Branch and worktree templates require {number} and {slug}')
    return {'status': 'resolved', 'repository': repository, 'effective': effective, 'sources': sources}


def config_path():
    return Path(os.environ.get('AGENT_SKILLS_CONFIG', str(Path.home() / '.config/agent-skills/config.json'))).expanduser()


def load_config(path):
    if not path.exists():
        return b'', {}
    data = path.read_bytes()
    return data, json_object(data)


def connection(value, label):
    if (not isinstance(value, dict) or not isinstance(value.get('nodes'), list)
            or type(value.get('totalCount')) is not int or value['totalCount'] != len(value['nodes'])):
        raise Problem('Incomplete GitHub ' + label)
    return value['nodes']


def read_issue(repository, number):
    response = json.loads(run(str(HERE / 'query.sh'), 'project-status', repository, str(number)))
    if response.get('errors'):
        raise Problem('GitHub returned errors', errors=response['errors'])
    issue = ((response.get('data') or {}).get('repository') or {}).get('issue')
    if not issue:
        raise Problem('Issue was not found or is inaccessible')
    if issue.get('number') != number or issue.get('state') not in ('OPEN', 'CLOSED'):
        raise Problem('Incomplete or unexpected GitHub issue identity')
    return issue


def issue_repository(issue):
    name = (issue.get('repository') or {}).get('nameWithOwner')
    if name:
        return repository_name(name)
    match = re.fullmatch(r'https://github.com/([^/]+/[^/]+)/issues/[0-9]+', issue.get('url', ''))
    if not match:
        raise Problem('Incomplete GitHub issue identity')
    return repository_name(match[1])


def choose(selector, objects, kind):
    if selector.startswith('id:'):
        matches = [obj for obj in objects if obj.get('id') == selector[3:]]
    else:
        matches = [obj for obj in objects if obj.get('name', '').casefold() == selector.casefold()]
    if len(matches) != 1:
        raise Problem('Expected one ' + kind + ' matching ' + selector, 'needs_input',
                      candidates=[{'id': obj.get('id'), 'name': obj.get('name')} for obj in (matches or objects)])
    if not matches[0].get('id'):
        raise Problem('Missing GitHub ID for ' + kind)
    return matches[0]


def board_inventory(issue, sync):
    result = []
    seen = set()
    for item in connection(issue.get('projectItems'), 'board memberships'):
        project = item.get('project') or {}
        owner = (project.get('owner') or {}).get('login')
        if not owner or type(project.get('number')) is not int or not project.get('id') or not item.get('id'):
            raise Problem('Inaccessible or incomplete assigned board')
        identity = owner.casefold() + '/' + str(project['number'])
        if identity in seen:
            raise Problem('Duplicate assigned board ' + identity)
        seen.add(identity)
        mapping = sync['boards'].get(identity)
        fields = [f for f in connection(project.get('fields'), 'board fields') if 'options' in f]
        values = connection(item.get('fieldValues'), 'board field values')
        result.append({'identity': identity, 'title': project.get('title'), 'projectId': project['id'],
                       'itemId': item['id'], 'fields': fields, 'values': values, 'mapping': mapping})
    return result


def plan_issue(issue, sync, event):
    boards = board_inventory(issue, sync)
    updates, unresolved = [], []
    for board in boards:
        mapping = board['mapping']
        if not sync['enabled'] or (mapping is not None and not mapping['enabled']):
            board['management'] = 'unmanaged'
            continue
        if mapping is None or not mapping.get('fields'):
            board['management'] = 'unconfigured'
            unresolved.append({'repository': issue_repository(issue), 'issue': issue['number'],
                               'board': board['identity'], 'reason': 'Select fields or leave this board unmanaged'})
            continue
        board['management'] = 'managed'
        seen_fields = set()
        for selector, events in mapping['fields'].items():
            field_selector = 'id:' + events['fieldId'] if 'fieldId' in events else selector
            field = choose(field_selector, board['fields'], 'field on ' + board['identity'])
            if field['id'] in seen_fields:
                raise Problem('Multiple mappings select the same field on ' + board['identity'])
            seen_fields.add(field['id'])
            required = ('start', 'complete') if event == 'config' else (event,)
            for current_event in required:
                if current_event not in events:
                    unresolved.append({'repository': issue_repository(issue), 'issue': issue['number'],
                                       'board': board['identity'], 'field': field['name'], 'event': current_event,
                                       'reason': 'Select a transition option'})
                    continue
                option = choose(events[current_event], field['options'], 'option for ' + field['name'])
                existing = [v for v in board['values'] if (v.get('field') or {}).get('id') == field['id']]
                if len(existing) > 1:
                    raise Problem('Duplicate current field value on ' + board['identity'])
                current = existing[0] if existing else {}
                updates.append({'repository': issue_repository(issue), 'issue': issue['number'],
                                'board': board['identity'], 'projectId': board['projectId'], 'itemId': board['itemId'],
                                'fieldId': field['id'], 'field': field['name'], 'optionId': option['id'],
                                'expected': option['name'], 'current': current.get('name'), 'event': current_event,
                                'status': 'unchanged' if current.get('optionId') == option['id'] else 'pending'})
    return boards, updates, unresolved


def config_command(args, raw_bytes, raw, repository, override):
    path = config_path()
    proposal = migrate(raw)
    patch = layer(json_object(args.set)) if args.set is not None else None
    if args.confirm and patch is None:
        raise Problem('--confirm requires the same --set patch as the preview')
    if patch is not None:
        if set(patch) - set(DEFAULTS):
            raise Problem('The patch may contain only workflow settings for the selected scope')
        if override:
            raise Problem('Use --override for invocation-only resolution, not a saved configuration patch')
        if args.scope == 'global':
            proposal = overlay(proposal, patch)
        else:
            group, key = ('organizations', repository.split('/')[0]) if args.scope == 'organization' else ('repositories', repository)
            proposal[group][key] = overlay(proposal[group].get(key, {}), patch)
    resolved = resolve(proposal, repository, override)
    boards, updates, unresolved = [], [], []
    if args.issue:
        issue = read_issue(repository, args.issue)
        if issue_repository(issue) != repository:
            raise Problem('GitHub returned an issue from another repository')
        boards, updates, unresolved = plan_issue(issue, resolved['effective']['projectSync'], 'config')
    changed_boards = (patch or {}).get('projectSync', {}).get('boards', {})
    if changed_boards and not args.issue:
        raise Problem('Board configuration requires --issue for assigned-board discovery')
    for identity in changed_boards:
        if identity not in {board['identity'] for board in boards}:
            raise Problem('Board ' + identity + ' is not assigned to the issue')
    result = dict(resolved, boards=boards, unresolved=unresolved)
    if patch is None:
        result['status'] = 'needs_input' if unresolved else ('configured' if args.issue else 'resolved')
        if unresolved:
            result['message'] = 'Use config to select mappings or leave assigned boards unmanaged'
        emit(result)
        return 2 if unresolved else 0
    # Incomplete unrelated boards remain visible so setup can save one choice at a time.
    if any(item['board'] in changed_boards for item in unresolved):
        raise Problem('Selected board mappings need explicit fields and transition values', 'needs_input', unresolved=unresolved)
    digest = hashlib.sha256(raw_bytes + json.dumps({'repository': repository, 'scope': args.scope,
                                                  'proposal': proposal, 'boards': boards}, sort_keys=True).encode()).hexdigest()
    preview = dict(result, status='preview', token=digest, scope=args.scope, configuration=proposal,
                   path=str(path), before=raw)
    if args.confirm is None:
        emit(preview)
        return 0
    if args.confirm != digest:
        raise Problem('Configuration or assigned-board discovery changed; review a fresh preview', 'stale_preview', preview=preview)
    path.parent.mkdir(parents=True, exist_ok=True)
    lock = path.with_name(path.name + '.lock')
    try:
        lock.mkdir()
    except FileExistsError:
        raise Problem('Another configuration write holds ' + str(lock))
    temporary = None
    try:
        if load_config(path)[0] != raw_bytes:
            raise Problem('Configuration changed; review a fresh preview', 'stale_preview')
        descriptor, temporary = tempfile.mkstemp(prefix=path.name + '.', dir=str(path.parent))
        with os.fdopen(descriptor, 'w') as output:
            json.dump(proposal, output, indent=2, ensure_ascii=False)
            output.write('\n')
            output.flush()
            os.fsync(output.fileno())
        if path.exists():
            os.chmod(temporary, path.stat().st_mode & 0o777)
        if load_config(path)[0] != raw_bytes:
            raise Problem('Configuration changed during the write; review a fresh preview', 'stale_preview')
        os.replace(temporary, path)
    finally:
        if temporary and Path(temporary).exists():
            Path(temporary).unlink()
        lock.rmdir()
    emit(dict(result, status='saved', scope=args.scope, path=str(path)))
    return 0


def transition_command():
    parser = argparse.ArgumentParser()
    parser.add_argument('event', choices=['start', 'complete', 'status'])
    parser.add_argument('repository')
    parser.add_argument('number', type=int)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--preflight', action='store_true')
    parser.add_argument('--override', default=os.environ.get('AGENT_SKILLS_PROJECT_OVERRIDE', '{}'))
    args = parser.parse_args(sys.argv[2:])
    repository = repository_name(args.repository)
    if args.number <= 0:
        raise Problem('Issue number must be positive')
    _, raw = load_config(config_path())
    override = json_object(args.override)
    resolved = resolve(raw, repository, override)
    sync = resolved['effective']['projectSync']
    if not sync['enabled']:
        emit({'status': 'disabled', 'updates': [], 'boards': [], 'unresolved': []})
        return 0
    focused = read_issue(repository, args.number)
    if issue_repository(focused) != repository:
        raise Problem('GitHub returned an issue from another repository')
    event = args.event
    if event == 'status':
        event = 'complete' if focused['state'] == 'CLOSED' and focused.get('stateReason') == 'COMPLETED' else 'start'
        if focused['state'] == 'CLOSED' and event != 'complete':
            emit({'status': 'not_completed', 'updates': [], 'boards': [], 'unresolved': []})
            return 0
    if event == 'complete' and not args.preflight:
        if focused['state'] != 'CLOSED' or focused.get('stateReason') != 'COMPLETED':
            raise Problem('A completion transition requires a confirmed completed issue')
    if event == 'start' and focused['state'] != 'OPEN':
        raise Problem('A start transition requires an open issue')
    issues = [focused]
    if event == 'start' and args.event != 'status' and sync['ancestors']:
        parent = focused.get('parent')
        while parent is not None:
            if not parent.get('url'):
                raise Problem('Incomplete GitHub ancestor hierarchy')
            if parent['state'] == 'OPEN':
                issues.append(parent)
            parent = parent.get('parent')
    boards, updates, unresolved = [], [], []
    for issue in issues:
        settings = resolve(raw, issue_repository(issue), override)['effective']['projectSync']
        if not settings['enabled']:
            continue
        inventory, actions, choices = plan_issue(issue, settings, event)
        boards.extend(dict(board, repository=issue_repository(issue), issue=issue['number']) for board in inventory)
        updates.extend(actions)
        unresolved.extend(choices)
    result = {'status': 'needs_input' if unresolved else 'planned', 'event': event,
              'boards': boards, 'updates': updates, 'unresolved': unresolved}
    if unresolved:
        result['message'] = 'Run config for the reported issues before this transition'
        emit(result)
        return 2
    if args.dry_run or args.preflight or args.event == 'status':
        emit(result)
        return 0
    for update in updates:
        if update['status'] == 'unchanged':
            continue
        try:
            run('gh', 'project', 'item-edit', '--id', update['itemId'], '--project-id', update['projectId'],
                '--field-id', update['fieldId'], '--single-select-option-id', update['optionId'])
            update['status'] = 'updated'
        except Problem as error:
            update['status'] = 'failed'
            update['error'] = str(error)
            result['status'] = 'partial_failure'
            emit(result)
            return 2
    result['status'] = 'applied'
    emit(result)
    return 0


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "transition":
        return transition_command()
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['config', 'resolve'])
    parser.add_argument('repository')
    parser.add_argument('--override', default=os.environ.get('AGENT_SKILLS_PROJECT_OVERRIDE', '{}'))
    parser.add_argument('--start-settings', action='store_true')
    parser.add_argument('--issue', type=int)
    parser.add_argument('--scope', choices=['global', 'organization', 'repository'], default='repository')
    parser.add_argument('--set')
    parser.add_argument('--confirm')
    args = parser.parse_args()
    repository = repository_name(args.repository)
    raw_bytes, raw = load_config(config_path())
    override = json_object(args.override)
    if args.issue is not None and args.issue <= 0:
        raise Problem('Issue number must be positive')
    if args.command == 'config':
        return config_command(args, raw_bytes, raw, repository, override)
    result = resolve(raw, repository, override)
    emit(result['effective'] if args.start_settings else result)


if __name__ == '__main__':
    try:
        sys.exit(main() or 0)
    except (Problem, ValueError, OSError) as error:
        emit(error.result if isinstance(error, Problem) else {'status': 'blocked', 'message': str(error)})
        sys.exit(2)
