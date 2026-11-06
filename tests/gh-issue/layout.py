#!/usr/bin/env python3
"""Exercise configurable branch and worktree layout with synthetic GitHub and Git state.

Every repository, worktree, issue, and configuration file lives in a temporary
directory. HOME points into that directory, so the workspace-file search cannot
reach a real file. A fake gh answers from one JSON issue graph.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[2] / 'skills/engineering/gh-issue/scripts'
KEY_PATTERN = r'^\[([A-Z]+-[0-9]+)\]'

FAKE_GH = r'''
import json, os, re, subprocess, sys
from pathlib import Path

args = sys.argv[1:]
state_path = Path(os.environ['FAKE_STATE'])
state = json.loads(state_path.read_text())

def log():
    with open(os.environ['FAKE_CALLS'], 'a') as handle:
        handle.write(json.dumps(args) + '\n')

def value(name):
    for argument in args:
        if argument.startswith(name + '='):
            return argument[len(name) + 1:]
    return None

def option(name):
    return args[args.index(name) + 1]

def repository(name):
    return state['repositories'][name.lower()]

def linked(name, issue):
    return {'totalCount': len(issue['linked']), 'nodes': [
        {'ref': {'name': branch, 'repository': {'nameWithOwner': name}}} for branch in issue['linked']]}

def summary(name, number):
    issue = repository(name)['issues'][str(number)]
    return {'number': number, 'title': issue['title'], 'state': issue['state'],
            'stateReason': issue.get('stateReason'), 'url': 'https://github.com/%s/issues/%s' % (name, number),
            'labels': {'nodes': []}}

def parent_chain(name, number, extra):
    parent = repository(name)['issues'][str(number)].get('parent')
    if parent is None:
        return None
    node = summary(name, parent)
    node.update(extra(name, parent))
    node['parent'] = parent_chain(name, parent, extra)
    return node

def children(name, number):
    return sorted(int(key) for key, issue in repository(name)['issues'].items() if issue.get('parent') == number)

def issue_payload(mode, name, number):
    data = repository(name)
    issue = data['issues'][str(number)]
    payload = summary(name, number)
    payload['linkedBranches'] = linked(name, issue)
    payload['assignees'] = {'totalCount': len(issue.get('assignees', [])),
                            'nodes': [{'login': login} for login in issue.get('assignees', [])]}
    kids = children(name, number)
    if mode == 'start':
        payload['subIssues'] = {'totalCount': len(kids)}
        payload['parent'] = parent_chain(name, number, lambda n, p: {
            'linkedBranches': linked(n, repository(n)['issues'][str(p)]),
            'subIssues': {'totalCount': len(children(n, p)), 'nodes': [{'number': c} for c in children(n, p)]}})
    elif mode == 'finish':
        payload['subIssues'] = {'totalCount': len(kids), 'nodes': [summary(name, kid) for kid in kids]}
        payload['parent'] = parent_chain(name, number, lambda n, p: {
            'linkedBranches': linked(n, repository(n)['issues'][str(p)])})
    elif mode == 'status':
        payload.update(body='', updatedAt='2026-11-01T00:00:00Z', blockedBy={'totalCount': 0, 'nodes': []})
        parent = issue.get('parent')
        payload['parent'] = None if parent is None else summary(name, parent)
        payload['subIssues'] = {'totalCount': len(kids), 'nodes': [dict(
            summary(name, kid), subIssues={'totalCount': len(children(name, kid))},
            blockedBy={'totalCount': 0, 'nodes': []},
            linkedBranches=linked(name, data['issues'][str(kid)])) for kid in kids]}
    else:
        sys.exit('unexpected query mode: ' + mode)
    return {'data': {'repository': {'nameWithOwner': name, 'defaultBranchRef': {'name': 'main'}, 'issue': payload}}}

if args[:2] == ['api', 'graphql']:
    query = value('query') or ''
    mode = Path(query.lstrip('@')).stem
    log()
    name = value('owner') + '/' + value('name')
    print(json.dumps(issue_payload(mode, name, int(value('number')))))
elif args[:2] == ['api', 'user']:
    print('test-user')
elif args[:2] == ['issue', 'edit']:
    log()
elif args[:2] == ['issue', 'develop']:
    log()
    name, number = option('--repo'), args[2]
    data = repository(name)
    branch, base = option('--name'), option('--base')
    git = os.environ['REAL_GIT']
    oid = subprocess.check_output([git, '--git-dir=' + data['remote'], 'rev-parse', 'refs/heads/' + base], text=True).strip()
    subprocess.run([git, '--git-dir=' + data['remote'], 'update-ref', 'refs/heads/' + branch, oid], check=True)
    data['issues'][number]['linked'].append(branch)
    state_path.write_text(json.dumps(state))
elif args[:2] == ['pr', 'list']:
    print('[]')
else:
    sys.stderr.write('unexpected gh call: %r\n' % args)
    sys.exit(70)
'''


class Layout(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='gh-issue-layout-tests-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.workspace = self.home / 'Github/example-workspace/app'
        self.workspace.mkdir(parents=True)
        self.config = self.root / 'config.json'
        self.config.write_text(json.dumps({'projectSync': {'enabled': False}}))
        self.state = self.root / 'state.json'
        self.calls = self.root / 'calls.jsonl'
        self.calls.write_text('')
        self.state.write_text(json.dumps({'repositories': {}}))
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        gh = bin_dir / 'gh'
        gh.write_text('#!' + sys.executable + '\n' + FAKE_GH)
        gh.chmod(0o755)
        real_git = shutil.which('git')
        # git remote get-url applies insteadOf. The scripts compare the configured GitHub URL.
        git = bin_dir / 'git'
        git.write_text('#!/bin/sh\nif [ "$1" = remote ] && [ "$2" = get-url ]; then\n'
                       '  exec "$REAL_GIT" config --get remote.origin.url\nfi\nexec "$REAL_GIT" "$@"\n')
        git.chmod(0o755)
        self.env = {**os.environ, 'HOME': str(self.home), 'AGENT_SKILLS_CONFIG': str(self.config),
                    'PATH': str(bin_dir) + os.pathsep + os.environ['PATH'], 'REAL_GIT': real_git,
                    'FAKE_STATE': str(self.state), 'FAKE_CALLS': str(self.calls),
                    'GIT_CONFIG_NOSYSTEM': '1'}
        self.env.pop('AGENT_SKILLS_PROJECT_OVERRIDE', None)

    # Fixture helpers

    def git(self, cwd, *args):
        return subprocess.check_output([self.env['REAL_GIT'], '-C', str(cwd), *args], text=True,
                                       env=self.env, stderr=subprocess.DEVNULL).strip()

    def repository(self, name, primary, issues):
        remote = self.root / 'remotes' / (name.replace('/', '-') + '.git')
        remote.parent.mkdir(exist_ok=True)
        subprocess.run([self.env['REAL_GIT'], 'init', '-q', '--bare', str(remote)], check=True, env=self.env)
        primary.mkdir(parents=True, exist_ok=True)
        url = 'https://github.com/' + name + '.git'
        self.git(primary, 'init', '-q', '-b', 'main')
        for key, setting in [('user.name', 'Test'), ('user.email', 'test@example.com'),
                             ('url.' + str(remote) + '.insteadOf', url)]:
            self.git(primary, 'config', key, setting)
        self.git(primary, 'remote', 'add', 'origin', url)
        (primary / 'base.txt').write_text('base\n')
        self.git(primary, 'add', 'base.txt')
        self.git(primary, 'commit', '-qm', 'Initial state')
        self.git(primary, 'push', '-qu', 'origin', 'main')
        state = json.loads(self.state.read_text())
        state['repositories'][name] = {'remote': str(remote), 'issues': {
            str(number): {'state': 'OPEN', 'linked': [], 'parent': None, **issue} for number, issue in issues.items()}}
        self.state.write_text(json.dumps(state))
        return primary

    def edit_issue(self, name, number, **changes):
        state = json.loads(self.state.read_text())
        state['repositories'][name]['issues'][str(number)].update(changes)
        self.state.write_text(json.dumps(state))

    def record(self, primary, branch):
        result = subprocess.run([self.env['REAL_GIT'], '-C', str(primary), 'config', 'branch.' + branch + '.gh-issue'],
                                capture_output=True, text=True, env=self.env)
        return result.stdout.strip()

    def write_workspace(self, settings):
        (self.workspace / '.gh-issue.json').write_text(json.dumps(settings))

    def key_workspace(self):
        self.write_workspace({
            'worktreePath': '{workspace}/.scratch/worktrees/{branch}/{checkout}',
            'taskBranchTemplate': 'feat/{key}',
            'branchKey': {'from': 'titlePrefix', 'pattern': KEY_PATTERN},
        })

    def run_script(self, cwd, command, *args, code=0):
        result = subprocess.run([str(SCRIPTS / command), *args], cwd=cwd, env=self.env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, code, 'stdout:\n' + result.stdout + '\nstderr:\n' + result.stderr)
        return result

    def call_log(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def mutations(self):
        return [call for call in self.call_log() if call[:2] in (['issue', 'develop'], ['issue', 'edit'])]

    @staticmethod
    def field(output, name):
        return next(line.split(': ', 1)[1] for line in output.splitlines() if line.startswith(name + ': '))

    @staticmethod
    def same_path(first, second):
        return os.path.realpath(first) == os.path.realpath(second)

    # Tests

    def test_default_settings_keep_branch_names_and_paths(self):
        primary = self.repository('example/plain', self.home / 'code/plain', {5: {'title': 'Add Feature'}})
        output = self.run_script(primary, 'start.sh', 'start', 'example/plain', '5').stdout
        self.assertEqual(self.field(output, 'Branch'), 'feat/issue-5-add-feature')
        self.assertTrue(self.same_path(self.field(output, 'Worktree'),
                                       self.home / 'worktrees/plain/issue-5-add-feature'))
        develop = [call for call in self.call_log() if call[:2] == ['issue', 'develop']]
        self.assertEqual(develop, [['issue', 'develop', '5', '--repo', 'example/plain', '--base', 'main',
                                    '--name', 'feat/issue-5-add-feature']])

    def test_shared_key_gives_one_branch_name_in_two_repositories(self):
        self.key_workspace()
        web = self.repository('example/app-web', self.workspace / 'web', {12: {'title': '[TICKET-42] Add export'}})
        api = self.repository('example/app-api', self.workspace / 'api', {7: {'title': '[TICKET-42] Add export API'}})
        web_output = self.run_script(web, 'start.sh', 'start', 'example/app-web', '12').stdout
        api_output = self.run_script(api, 'start.sh', 'start', 'example/app-api', '7').stdout
        self.assertEqual(self.field(web_output, 'Branch'), 'feat/ticket-42')
        self.assertEqual(self.field(api_output, 'Branch'), 'feat/ticket-42')
        # A slash in the branch creates nested folders, and {checkout} separates the repositories.
        scratch = self.workspace / '.scratch/worktrees/feat/ticket-42'
        self.assertTrue(self.same_path(self.field(web_output, 'Worktree'), scratch / 'web'))
        self.assertTrue(self.same_path(self.field(api_output, 'Worktree'), scratch / 'api'))
        self.assertEqual(self.git(scratch / 'api', 'branch', '--show-current'), 'feat/ticket-42')

    def test_title_without_key_needs_input_and_changes_nothing(self):
        self.key_workspace()
        web = self.repository('example/app-web', self.workspace / 'web', {13: {'title': 'Add import'}})
        refs_before = self.git(web, 'ls-remote', 'origin')
        result = self.run_script(web, 'start.sh', 'start', 'example/app-web', '13', code=2)
        answer = json.loads(result.stdout)
        self.assertEqual((answer['status'], answer['field']), ('needs_input', 'branch'))
        self.assertIn('branchKey.pattern', answer['question'])
        self.assertEqual(self.mutations(), [])
        self.assertEqual(self.git(web, 'ls-remote', 'origin'), refs_before)
        self.assertFalse((self.workspace / '.scratch').exists())

    def test_linked_branch_without_number_is_found_by_start_status_and_finish(self):
        self.key_workspace()
        web = self.repository('example/app-web', self.workspace / 'web', {12: {'title': '[TICKET-42] Add export'}})
        self.run_script(web, 'start.sh', 'start', 'example/app-web', '12')
        worktree = self.workspace / '.scratch/worktrees/feat/ticket-42/web'
        self.assertEqual(json.loads(self.state.read_text())['repositories']['example/app-web']['issues']['12']['linked'],
                         ['feat/ticket-42'])
        output = self.run_script(web, 'start.sh', 'resume', 'example/app-web', '12').stdout
        self.assertEqual(self.field(output, 'Status'), 'existing_worktree')
        self.assertTrue(self.same_path(self.field(output, 'Worktree'), worktree))
        output = self.run_script(web, 'status.sh', 'example/app-web', '12').stdout
        self.assertIn('[feat/ticket-42]', self.field(output, 'Local worktrees'))
        self.assertEqual(self.field(output, 'Started'), 'yes')
        output = self.run_script(web, 'finish.sh', '--dry-run', 'example/app-web', '12').stdout
        self.assertEqual(self.field(output, 'Branch'), 'feat/ticket-42')
        self.assertTrue(self.same_path(self.field(output, 'Worktree'), worktree))

    def test_linked_branch_without_number_under_default_templates(self):
        primary = self.repository('example/plain', self.home / 'code/plain', {
            8: {'title': 'Export data', 'linked': ['topic/export']}})
        self.git(primary, 'push', '-q', 'origin', 'main:refs/heads/topic/export')
        output = self.run_script(primary, 'start.sh', 'start', 'example/plain', '8').stdout
        self.assertEqual((self.field(output, 'Status'), self.field(output, 'Branch')), ('already_started', 'topic/export'))
        output = self.run_script(primary, 'start.sh', 'resume', 'example/plain', '8').stdout
        self.assertEqual(self.field(output, 'Branch'), 'topic/export')
        output = self.run_script(primary, 'status.sh', 'example/plain', '8').stdout
        self.assertIn('[topic/export]', self.field(output, 'Local worktrees'))
        output = self.run_script(primary, 'finish.sh', '--dry-run', 'example/plain', '8').stdout
        self.assertEqual(self.field(output, 'Branch'), 'topic/export')
        self.assertEqual([call for call in self.call_log() if call[:2] == ['issue', 'develop']], [])

    def test_start_refuses_a_branch_that_another_issue_owns(self):
        self.key_workspace()
        web = self.repository('example/app-web', self.workspace / 'web', {
            12: {'title': '[TICKET-42] Add export'}, 14: {'title': '[TICKET-42] Document export'}})
        self.run_script(web, 'start.sh', 'start', 'example/app-web', '12')
        self.assertEqual(self.record(web, 'feat/ticket-42'), '12')
        before = self.mutations()
        result = self.run_script(web, 'start.sh', 'start', 'example/app-web', '14', code=2)
        self.assertIn('feat/ticket-42 belongs to issue #12 in this clone, not issue #14', result.stderr)
        # An explicit choice gets the same answer.
        result = self.run_script(web, 'start.sh', 'resume', '--branch', 'feat/ticket-42', 'example/app-web', '14', code=2)
        self.assertIn('belongs to issue #12 in this clone', result.stderr)
        self.assertEqual(self.mutations(), before)
        # The record does not depend on the title of the owner.
        self.edit_issue('example/app-web', 12, title='Add export')
        self.run_script(web, 'start.sh', 'start', 'example/app-web', '14', code=2)
        self.assertEqual(self.mutations(), before)

    def test_status_and_finish_ignore_a_branch_that_another_issue_owns(self):
        self.key_workspace()
        web = self.repository('example/app-web', self.workspace / 'web', {
            12: {'title': '[TICKET-42] Add export'}, 14: {'title': '[TICKET-42] Document export'}})
        self.run_script(web, 'start.sh', 'start', 'example/app-web', '12')
        output = self.run_script(web, 'status.sh', 'example/app-web', '14').stdout
        self.assertEqual((self.field(output, 'Local worktrees'), self.field(output, 'Started')), ('none', 'no'))
        result = self.run_script(web, 'finish.sh', '--dry-run', 'example/app-web', '14', code=2)
        self.assertIn('no worktree matches issue #14', result.stderr)
        result = self.run_script(web, 'finish.sh', '--dry-run', '--branch', 'feat/ticket-42', 'example/app-web', '14', code=2)
        self.assertIn('belongs to issue #12 in this clone', result.stderr)
        self.assertNotIn('close', result.stdout)

    def test_link_and_record_for_different_issues_is_a_conflict(self):
        self.key_workspace()
        web = self.repository('example/app-web', self.workspace / 'web', {
            12: {'title': '[TICKET-42] Add export'}, 14: {'title': '[TICKET-42] Document export'}})
        self.run_script(web, 'start.sh', 'start', 'example/app-web', '12')
        # GitHub also links the branch to #14, but this clone records it for #12.
        self.edit_issue('example/app-web', 14, linked=['feat/ticket-42'])
        before = self.mutations()
        for mode in ('start', 'resume'):
            result = self.run_script(web, 'start.sh', mode, 'example/app-web', '14', code=2)
            self.assertIn('issue #14 links branch feat/ticket-42, but this clone records it for issue #12', result.stderr)
        self.assertEqual(self.mutations(), before)
        self.assertEqual(self.record(web, 'feat/ticket-42'), '12')
        output = self.run_script(web, 'status.sh', 'example/app-web', '14').stdout
        self.assertEqual(self.field(output, 'Local worktrees'), 'none')
        result = self.run_script(web, 'finish.sh', '--dry-run', 'example/app-web', '14', code=2)
        self.assertIn('records it for issue #12', result.stderr)
        self.assertNotIn('close', result.stdout)
        # An explicit branch cannot bypass the conflict in finish or in start.
        self.git(web, 'worktree', 'add', '-q', '-b', 'topic/other', str(self.root / 'other'), 'main')
        result = self.run_script(web, 'finish.sh', '--dry-run', '--branch', 'topic/other', 'example/app-web', '14', code=2)
        self.assertIn('records it for issue #12', result.stderr)
        self.assertNotIn('close', result.stdout)
        for branch in ('topic/new', 'topic/other'):
            result = self.run_script(web, 'start.sh', 'resume', '--branch', branch, 'example/app-web', '14', code=2)
            self.assertIn('records it for issue #12', result.stderr)
        self.assertEqual(self.mutations(), before)
        self.assertEqual(self.record(web, 'topic/other'), '')

    def test_record_of_a_removed_branch_does_not_block_its_name(self):
        self.write_workspace({'taskBranchTemplate': 'feat/shared'})
        web = self.repository('example/app-web', self.workspace / 'web', {
            12: {'title': 'First change', 'linked': ['feat/shared']}, 14: {'title': 'Later change'}})
        self.git(web, 'push', '-q', 'origin', 'main:refs/heads/feat/shared')
        self.git(web, 'fetch', '-q', 'origin')
        # Start records the remote-only branch, which has no local copy.
        output = self.run_script(web, 'start.sh', 'start', 'example/app-web', '12').stdout
        self.assertEqual(self.field(output, 'Status'), 'already_started')
        self.assertEqual(self.record(web, 'feat/shared'), '12')
        # The remote branch goes away, as after cleanup or an automatic deletion on merge.
        self.edit_issue('example/app-web', 12, state='CLOSED', linked=[])
        self.git(web, 'push', '-q', 'origin', '--delete', 'feat/shared')
        output = self.run_script(web, 'start.sh', 'start', 'example/app-web', '14').stdout
        self.assertEqual((self.field(output, 'Status'), self.field(output, 'Branch')), ('started', 'feat/shared'))
        self.assertEqual(self.record(web, 'feat/shared'), '14')

    def test_finish_keeps_a_linked_branch_without_a_worktree(self):
        primary = self.repository('example/plain', self.home / 'code/plain', {5: {'title': 'First task'}})
        output = self.run_script(primary, 'start.sh', 'start', 'example/plain', '5').stdout
        self.git(primary, 'worktree', 'remove', self.field(output, 'Worktree'))
        self.git(primary, 'worktree', 'add', '-q', '-b', 'topic/other', str(self.root / 'other'), 'main')
        answer = json.loads(self.run_script(primary, 'finish.sh', '--dry-run', '--branch', 'topic/other',
                                            'example/plain', '5', code=2).stdout)
        self.assertEqual((answer['field'], answer['candidates']), ('branch', ['feat/issue-5-first-task']))
        result = self.run_script(primary, 'finish.sh', '--dry-run', 'example/plain', '5', code=2)
        self.assertIn('feat/issue-5-first-task with no worktree; resume issue #5', result.stderr)
        result = self.run_script(primary, 'finish.sh', '--dry-run', '--branch', 'feat/issue-5-first-task',
                                 'example/plain', '5', code=2)
        self.assertIn('no worktree holds branch feat/issue-5-first-task', result.stderr)

    def test_constant_template_cannot_give_one_branch_to_two_issues(self):
        self.write_workspace({'taskBranchTemplate': 'feat/shared'})
        web = self.repository('example/app-web', self.workspace / 'web', {
            21: {'title': 'First change'}, 22: {'title': 'Unrelated change'}})
        self.run_script(web, 'start.sh', 'start', 'example/app-web', '21')
        before = self.mutations()
        result = self.run_script(web, 'start.sh', 'resume', 'example/app-web', '22', code=2)
        self.assertIn('feat/shared belongs to issue #21 in this clone', result.stderr)
        self.assertEqual(self.mutations(), before)

    def test_shared_name_without_link_or_record_needs_an_answer(self):
        # Another clone created the branch, so this clone has no record of its issue.
        self.key_workspace()
        web = self.repository('example/app-web', self.workspace / 'web', {12: {'title': '[TICKET-42] Add export'}})
        self.git(web, 'push', '-q', 'origin', 'main:refs/heads/feat/ticket-42')
        self.git(web, 'fetch', '-q', 'origin')
        answer = json.loads(self.run_script(web, 'start.sh', 'start', 'example/app-web', '12', code=2).stdout)
        self.assertEqual((answer['field'], answer['candidates']), ('branch', ['feat/ticket-42']))
        self.assertIn('Another open issue can own it', answer['question'])
        self.assertEqual(self.mutations(), [])
        output = self.run_script(web, 'status.sh', 'example/app-web', '12').stdout
        self.assertEqual(self.field(output, 'Started'), 'no')
        # An explicit answer records the branch, and later commands accept it.
        output = self.run_script(web, 'start.sh', 'resume', '--branch', 'feat/ticket-42', 'example/app-web', '12').stdout
        self.assertEqual(self.field(output, 'Status'), 'resumed')
        self.assertEqual(self.record(web, 'feat/ticket-42'), '12')
        output = self.run_script(web, 'status.sh', 'example/app-web', '12').stdout
        self.assertEqual(self.field(output, 'Started'), 'yes')
        output = self.run_script(web, 'finish.sh', '--dry-run', 'example/app-web', '12').stdout
        self.assertEqual(self.field(output, 'Branch'), 'feat/ticket-42')

    def test_finish_branch_must_be_an_issue_branch_when_one_exists(self):
        primary = self.repository('example/plain', self.home / 'code/plain', {
            5: {'title': 'First task'}, 6: {'title': 'Second task'}})
        self.run_script(primary, 'start.sh', 'start', 'example/plain', '5')
        self.run_script(primary, 'start.sh', 'start', 'example/plain', '6')
        # A branch recorded for another issue is refused.
        result = self.run_script(primary, 'finish.sh', '--dry-run', '--branch', 'feat/issue-6-second-task',
                                 'example/plain', '5', code=2)
        self.assertIn('belongs to issue #6 in this clone, not issue #5', result.stderr)
        # A branch with no record cannot replace the linked branch of the issue.
        self.git(primary, 'worktree', 'add', '-q', '-b', 'topic/other', str(self.root / 'other'), 'main')
        answer = json.loads(self.run_script(primary, 'finish.sh', '--dry-run', '--branch', 'topic/other',
                                            'example/plain', '5', code=2).stdout)
        self.assertEqual((answer['field'], answer['candidates']), ('branch', ['feat/issue-5-first-task']))

    def test_board_transitions_accept_a_layout_split_across_files(self):
        # The local file uses {key}, and only the workspace file defines branchKey.
        self.config.write_text(json.dumps({'projectSync': {'enabled': False},
                                           'repositories': {'example/app-web': {'taskBranchTemplate': 'feat/{key}'}}}))
        self.write_workspace({'branchKey': {'from': 'titlePrefix', 'pattern': KEY_PATTERN}})
        web = self.repository('example/app-web', self.workspace / 'web', {12: {'title': '[TICKET-42] Add export'}})
        self.run_script(web, 'project-start.sh', '--dry-run', 'example/app-web', '12')
        output = self.run_script(web, 'start.sh', 'start', 'example/app-web', '12').stdout
        self.assertEqual(self.field(output, 'Branch'), 'feat/ticket-42')

    def test_start_refuses_a_destination_that_holds_another_branch(self):
        self.config.write_text(json.dumps({'projectSync': {'enabled': False}, 'worktreeRoot': str(self.root / 'wt'),
                                           'repositories': {'example/plain': {'worktreePath': '{root}/shared'}}}))
        primary = self.repository('example/plain', self.home / 'code/plain', {
            5: {'title': 'First task'}, 6: {'title': 'Second task'}})
        self.run_script(primary, 'start.sh', 'start', 'example/plain', '5')
        before = self.mutations()
        result = self.run_script(primary, 'start.sh', 'start', 'example/plain', '6', code=2)
        self.assertIn('already holds a worktree on branch feat/issue-5-first-task', result.stderr)
        self.assertEqual(self.mutations(), before)

    def test_start_rejects_a_relative_rendered_path(self):
        self.config.write_text(json.dumps({'projectSync': {'enabled': False},
                                           'repositories': {'example/plain': {'worktreePath': 'trees/{repo}/{number}'}}}))
        primary = self.repository('example/plain', self.home / 'code/plain', {5: {'title': 'First task'}})
        result = self.run_script(primary, 'start.sh', 'start', 'example/plain', '5', code=2)
        self.assertIn('not absolute: trees/plain/5', result.stderr)
        self.assertEqual(self.mutations(), [])

    def test_path_template_renders_every_variable(self):
        self.write_workspace({
            'worktreePath': '{root}/{owner}/{repo}/{checkout}/{branch}/{number}-{slug}-{key}/in{workspace}',
            'branchKey': {'from': 'titlePrefix', 'pattern': KEY_PATTERN},
        })
        self.config.write_text(json.dumps({'worktreeRoot': '/root'}))
        result = self.run_script(self.root, 'worktree-path.sh', 'Example/App-Web', '--checkout=' + str(self.workspace / 'web'),
                                 '--number=12', '--title=[TICKET-42] Add export', '--branch=feat/ticket-42')
        rendered = json.loads(result.stdout)
        self.assertEqual(rendered['path'], '/root/Example/App-Web/web/feat/ticket-42/12-ticket-42-add-export-ticket-42/in' +
                         str(self.workspace))
        self.assertTrue(rendered['source'].startswith('workspace:'))

    def test_key_is_the_lowercase_capture(self):
        self.key_workspace()
        self.repository('example/app-web', self.workspace / 'web', {})
        request = {'names': [], 'issues': [{'number': 42, 'title': '[TICKET-42] Add export', 'compound': False, 'linked': []}]}
        result = subprocess.run([str(SCRIPTS / 'branch-discovery.sh'), 'example/app-web',
                                 '--checkout=' + str(self.workspace / 'web')], input=json.dumps(request),
                                cwd=self.root, env=self.env, capture_output=True, text=True, check=True)
        issue = json.loads(result.stdout)['issues'][0]
        self.assertEqual((issue['key'], issue['rendered']), ('ticket-42', 'feat/ticket-42'))

    def test_workspace_placeholder_requires_the_workspace_file(self):
        for tier in ({'worktreePath': '{workspace}/trees'},
                     {'organizations': {'example': {'worktreePath': '{workspace}/trees'}}},
                     {'repositories': {'example/app-web': {'worktreePath': '{workspace}/trees'}}}):
            with self.subTest(tier=tier):
                self.config.write_text(json.dumps(tier))
                result = self.run_script(self.root, 'config.sh', 'example/app-web', code=2)
                self.assertIn('{workspace}', json.loads(result.stdout)['message'])
        # A branch template from the workspace file cannot use {workspace} either.
        self.config.write_text('{}')
        self.write_workspace({'taskBranchTemplate': '{workspace}/{number}'})
        result = self.run_script(self.root, 'config.sh', 'example/app-web',
                                 '--checkout=' + str(self.workspace / 'web'), code=2)
        self.assertIn('taskBranchTemplate cannot use {workspace}', json.loads(result.stdout)['message'])

    def test_workspace_file_rejects_machine_settings_and_board_mappings(self):
        for setting, expected in [({'worktreeRoot': '/trees'}, 'worktreeRoot'),
                                  ({'projectSync': {'boards': {'example/4': {'enabled': False}}}}, 'board mappings (projectSync)'),
                                  ({'worktreeTemplate': 'x-{number}'}, 'worktreeTemplate')]:
            with self.subTest(setting=setting):
                self.write_workspace(setting)
                result = self.run_script(self.root, 'config.sh', 'example/app-web',
                                         '--checkout=' + str(self.workspace / 'web'), code=2)
                message = json.loads(result.stdout)['message']
                self.assertIn(expected, message)
                self.assertIn('.gh-issue.json', message)

    def test_workspace_tier_sits_between_organization_and_repository(self):
        self.config.write_text(json.dumps({
            'organizations': {'example': {'taskBranchTemplate': 'org/{number}-{slug}', 'taskBaseBranch': 'org-base',
                                          'integrationBranchTemplate': 'org-epic/{number}-{slug}'}},
            'repositories': {'example/app-web': {'taskBaseBranch': 'repo-base'}},
        }))
        self.write_workspace({'taskBranchTemplate': 'ws/{number}-{slug}', 'taskBaseBranch': 'ws-base'})
        web = self.repository('example/app-web', self.workspace / 'web', {})
        before = (self.workspace / '.gh-issue.json').read_bytes()
        # Config finds the workspace file from the current checkout and reports it as a source.
        result = json.loads(self.run_script(web, 'config.sh', 'example/app-web').stdout)
        workspace_file = result['workspace']['file']
        self.assertTrue(self.same_path(workspace_file, self.workspace / '.gh-issue.json'))
        self.assertEqual(result['effective']['taskBranchTemplate'], 'ws/{number}-{slug}')
        self.assertEqual(result['sources']['taskBranchTemplate'], 'workspace:' + workspace_file)
        self.assertEqual(result['effective']['taskBaseBranch'], 'repo-base')
        self.assertEqual(result['sources']['taskBaseBranch'], 'repository:example/app-web')
        self.assertEqual(result['sources']['integrationBranchTemplate'], 'organization:example')
        self.assertEqual((self.workspace / '.gh-issue.json').read_bytes(), before)

    def test_config_save_never_writes_the_workspace_file(self):
        self.key_workspace()
        web = self.repository('example/app-web', self.workspace / 'web', {})
        before = (self.workspace / '.gh-issue.json').read_bytes()
        patch = json.dumps({'taskBaseBranch': 'develop'})
        preview = json.loads(self.run_script(web, 'config.sh', 'example/app-web', '--set', patch).stdout)
        self.run_script(web, 'config.sh', 'example/app-web', '--set', patch, '--confirm', preview['token'])
        self.assertEqual((self.workspace / '.gh-issue.json').read_bytes(), before)
        saved = json.loads(self.config.read_text())
        self.assertEqual(saved['repositories']['example/app-web'], {'taskBaseBranch': 'develop'})
        self.assertNotIn('worktreePath', json.dumps(saved))

    def test_template_match_requires_the_number_in_its_position(self):
        primary = self.repository('example/plain', self.home / 'code/plain', {
            3: {'title': 'Fix timeout'}, 12: {'title': 'Retry 3 times'}})
        worktree = self.root / 'issue-12'
        self.git(primary, 'worktree', 'add', '-q', '-b', 'feat/issue-12-retry-3-times', str(worktree), 'main')
        # Without a record, the branch is only a possible branch of issue #3: never a match.
        answer = json.loads(self.run_script(primary, 'start.sh', 'start', 'example/plain', '3', code=2).stdout)
        self.assertEqual(answer['candidates'], ['feat/issue-12-retry-3-times', 'feat/issue-3-fix-timeout'])
        output = self.run_script(primary, 'status.sh', 'example/plain', '3').stdout
        self.assertEqual((self.field(output, 'Local worktrees'), self.field(output, 'Started')), ('none', 'no'))
        answer = json.loads(self.run_script(primary, 'finish.sh', '--dry-run', 'example/plain', '3', code=2).stdout)
        self.assertEqual((answer['field'], answer['candidates']), ('branch', ['feat/issue-12-retry-3-times']))
        # For issue #12 the branch matches in every command.
        output = self.run_script(primary, 'start.sh', 'resume', 'example/plain', '12').stdout
        self.assertEqual(self.field(output, 'Branch'), 'feat/issue-12-retry-3-times')
        output = self.run_script(primary, 'status.sh', 'example/plain', '12').stdout
        self.assertIn('[feat/issue-12-retry-3-times]', self.field(output, 'Local worktrees'))
        output = self.run_script(primary, 'finish.sh', '--dry-run', 'example/plain', '12').stdout
        self.assertEqual(self.field(output, 'Branch'), 'feat/issue-12-retry-3-times')
        # After start records #12, issue #3 no longer sees the branch at all.
        self.assertEqual(self.record(primary, 'feat/issue-12-retry-3-times'), '12')
        result = self.run_script(primary, 'finish.sh', '--dry-run', 'example/plain', '3', code=2)
        self.assertIn('no worktree matches issue #3', result.stderr)
        self.assertEqual(self.mutations(), [call for call in self.mutations() if call[2] == '12'])

    def test_possible_branch_needs_input_then_either_answer_works(self):
        primary = self.repository('example/plain', self.home / 'code/plain', {3: {'title': 'Fix timeout'}})
        self.git(primary, 'branch', 'fix/3-timeout')
        answer = json.loads(self.run_script(primary, 'start.sh', 'start', 'example/plain', '3', code=2).stdout)
        self.assertEqual((answer['status'], answer['field']), ('needs_input', 'branch'))
        self.assertEqual(answer['candidates'], ['fix/3-timeout', 'feat/issue-3-fix-timeout'])
        self.assertIn('fix/3-timeout', answer['question'])
        self.assertIn('Choose feat/issue-3-fix-timeout to create a new branch', answer['question'])
        self.assertEqual(self.mutations(), [])
        # The existing possible branch can be chosen explicitly.
        output = self.run_script(primary, 'start.sh', 'resume', '--branch', 'fix/3-timeout', 'example/plain', '3').stdout
        worktree = Path(self.field(output, 'Worktree'))
        self.assertEqual(self.git(worktree, 'branch', '--show-current'), 'fix/3-timeout')
        # Status does not count a possible branch as started work.
        output = self.run_script(primary, 'status.sh', 'example/plain', '3').stdout
        self.assertEqual((self.field(output, 'Local worktrees'), self.field(output, 'Started')), ('none', 'no'))
        # Finish asks instead of selecting the possible worktree, then accepts the explicit branch.
        answer = json.loads(self.run_script(primary, 'finish.sh', '--dry-run', 'example/plain', '3', code=2).stdout)
        self.assertEqual((answer['field'], answer['candidates']), ('branch', ['fix/3-timeout']))
        output = self.run_script(primary, 'finish.sh', '--dry-run', '--branch', 'fix/3-timeout', 'example/plain', '3').stdout
        self.assertEqual(self.field(output, 'Branch'), 'fix/3-timeout')

    def test_possible_branch_answer_can_create_the_new_branch(self):
        primary = self.repository('example/plain', self.home / 'code/plain', {3: {'title': 'Fix timeout'}})
        self.git(primary, 'branch', 'fix/3-timeout')
        output = self.run_script(primary, 'start.sh', 'start', '--branch', 'feat/issue-3-fix-timeout',
                                 'example/plain', '3').stdout
        self.assertEqual(self.field(output, 'Status'), 'started')
        self.assertEqual(self.field(output, 'Branch'), 'feat/issue-3-fix-timeout')
        develop = [call for call in self.call_log() if call[:2] == ['issue', 'develop']]
        self.assertEqual(develop[0][-1], 'feat/issue-3-fix-timeout')

    def test_rendered_branch_must_be_a_valid_ref(self):
        self.write_workspace({'taskBranchTemplate': 'feat/{key}',
                              'branchKey': {'from': 'titlePrefix', 'pattern': r'^\[([^\]]+)\]'}})
        web = self.repository('example/app-web', self.workspace / 'web', {9: {'title': '[TWO WORDS] Bad key'}})
        result = self.run_script(web, 'start.sh', 'start', 'example/app-web', '9', code=2)
        self.assertIn('not a valid branch name: feat/two words', result.stderr)
        self.assertEqual(self.mutations(), [])


if __name__ == '__main__':
    unittest.main()
