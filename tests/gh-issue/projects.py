#!/usr/bin/env python3
"""Exercise public gh-issue commands with synthetic GitHub and Git state."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import shutil
import unittest

SCRIPTS = Path(__file__).resolve().parents[2] / 'skills/engineering/gh-issue/scripts'


class Projects(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='gh-issue-project-tests-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'config.json'
        self.config.write_text('{}')
        self.fixture = self.root / 'github.json'
        self.calls = self.root / 'calls.jsonl'
        self.fixture.write_text(json.dumps(self.github_issue()))
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        gh = bin_dir / 'gh'
        gh.write_text('#!' + __import__('sys').executable + '\n' + r"""
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
p = Path(os.environ['FAKE_GITHUB'])
data = json.loads(p.read_text())
if args[:2] == ['api', 'graphql']:
    print(json.dumps(data))
elif args[:2] == ['pr', 'list']:
    print(os.environ.get('FAKE_PRS', '[]'))
elif args[:2] == ['issue', 'close']:
    with open(os.environ['FAKE_CALLS'], 'a') as f: f.write(json.dumps(args) + '\n')
    data['data']['repository']['issue'].update(state='CLOSED', stateReason='COMPLETED')
    p.write_text(json.dumps(data))
elif args[:2] == ['issue', 'develop']:
    with open(os.environ['FAKE_CALLS'], 'a') as f: f.write(json.dumps(args) + '\n')
    if os.environ.get('FAIL_DEVELOP'):
        sys.stderr.write('simulated branch creation failure')
        sys.exit(1)
    import subprocess
    branch = args[args.index('--name') + 1]
    base = args[args.index('--base') + 1]
    git = os.environ['REAL_GIT']
    remote = os.environ['FAKE_REMOTE']
    oid = subprocess.check_output([git, '--git-dir='+remote, 'rev-parse', 'refs/heads/'+base], text=True).strip()
    subprocess.run([git,'--git-dir='+remote,'update-ref','refs/heads/'+branch,oid],check=True)
    data['data']['repository']['issue']['linkedBranches'] = {'totalCount':1,'nodes':[
        {'ref':{'name':branch,'repository':{'nameWithOwner':'org/repo'}}}]}
    p.write_text(json.dumps(data))
elif args[:2] == ['project', 'item-edit']:
    with open(os.environ['FAKE_CALLS'], 'a') as f: f.write(json.dumps(args) + '\n')
    item_id = args[args.index('--id') + 1]
    if os.environ.get('FAIL_ITEM') == item_id:
        sys.stderr.write('simulated write failure')
        sys.exit(1)
    field_id = args[args.index('--field-id') + 1]
    option_id = args[args.index('--single-select-option-id') + 1]
    issue = data['data']['repository']['issue']
    while issue:
        for item in issue['projectItems']['nodes']:
            if item['id'] != item_id: continue
            field = next(f for f in item['project']['fields']['nodes'] if f['id'] == field_id)
            option = next(o for o in field['options'] if o['id'] == option_id)
            values = [v for v in item['fieldValues']['nodes'] if v['field']['id'] != field_id]
            values.append({'field': {'id':field_id,'name':field['name']}, 'optionId':option_id,'name':option['name']})
            item['fieldValues'] = {'totalCount':len(values),'nodes':values}
        issue = issue.get('parent')
    p.write_text(json.dumps(data))
else:
    sys.stderr.write('unexpected gh call: ' + repr(args))
    sys.exit(70)
""")
        gh.chmod(0o755)
        self.env = {**os.environ, 'AGENT_SKILLS_CONFIG': str(self.config),
                    'PATH': str(bin_dir) + os.pathsep + os.environ['PATH'],
                    'FAKE_GITHUB':str(self.fixture), 'FAKE_CALLS':str(self.calls)}

    @staticmethod
    def github_issue():
        items = []
        for number, name in [(4, 'Status'), (5, 'Delivery stage')]:
            field_id = 'field-' + str(number)
            items.append({'id':'item-' + str(number), 'project': {
                'id':'project-' + str(number), 'number':number, 'title':'Board ' + str(number),
                'owner':{'login':'ORG'}, 'fields':{'totalCount':1,'nodes':[
                    {'id':field_id,'name':name,'options':[
                        {'id':'todo','name':'Todo'}, {'id':'active','name':'In progress'}, {'id':'done','name':'Done'}]}
                ]}}, 'fieldValues':{'totalCount':1,'nodes':[
                    {'field':{'id':field_id,'name':name},'optionId':'todo','name':'Todo'}]}})
        return {'data':{'repository':{'nameWithOwner':'org/repo','defaultBranchRef':{'name':'main'},'issue':{
            'number':1,'title':'Test issue','state':'OPEN','stateReason':None,
            'url':'https://github.com/org/repo/issues/1','repository':{'nameWithOwner':'org/repo'},
            'projectItems':{'totalCount':len(items),'nodes':items},'parent':None,
            'subIssues':{'totalCount':0,'nodes':[]},'labels':{'nodes':[]},
            'blockedBy':{'totalCount':0,'nodes':[]},'linkedBranches':{'totalCount':0,'nodes':[]},
            'assignees':{'totalCount':1,'nodes':[{'login':'tester'}]}}}}}

    def mapping(self):
        return {'projectSync': {'boards': {
            'org/4': {'fields': {'STATUS': {'start': 'IN PROGRESS', 'complete': 'done'}}},
            'org/5': {'enabled': False}
        }}}


    def run_command(self, command, *args, code=0, decode=True):
        result = subprocess.run([str(SCRIPTS / command), *args], env=self.env,
                                capture_output=True, text=True, cwd=self.root)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return json.loads(result.stdout) if decode else result.stdout

    def git(self, *args):
        return subprocess.check_output([self.env['REAL_GIT'], '-C', str(self.root), *args], text=True).strip()

    def setup_repository(self):
        self.env['REAL_GIT'] = shutil.which('git')
        remote = self.root / 'remote.git'
        self.env['FAKE_REMOTE'] = str(remote)
        subprocess.run([self.env['REAL_GIT'],'init','-q','--bare',str(remote)],check=True)
        self.git('init','-q','-b','main')
        self.git('config','user.name','Test')
        self.git('config','user.email','test@example.com')
        self.git('config','url.' + str(remote) + '.insteadOf','https://github.com/org/repo.git')
        self.git('remote','add','origin','https://github.com/org/repo.git')
        (self.root / 'base.txt').write_text('base\n')
        self.git('add','base.txt')
        self.git('commit','-qm','Initial')
        self.git('push','-qu','origin','main')
        git_wrapper = self.root / 'bin/git'
        git_wrapper.write_text('#!/bin/sh\nif [ "$1" = remote ] && [ "$2" = get-url ]; then\n  exec "$REAL_GIT" config --get remote.origin.url\nfi\nexec "$REAL_GIT" "$@"\n')
        git_wrapper.chmod(0o755)
        mapping = self.mapping()
        mapping.update(worktreeManager='git', worktreeRoot=str(self.root / 'worktrees'))
        self.config.write_text(json.dumps(mapping))

    def test_public_start_resume_and_status_share_assigned_board_resolution(self):
        self.setup_repository()
        output = self.run_command('start.sh','start','org/repo','1',decode=False)
        self.assertIn('Status: started', output)
        worktree = Path(next(line.split(': ',1)[1] for line in output.splitlines() if line.startswith('Worktree: ')))
        self.assertEqual(subprocess.check_output([self.env['REAL_GIT'],'-C',str(worktree),'branch','--show-current'],text=True).strip(), 'feat/issue-1-test-issue')
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual([call[:2] for call in calls], [['issue','develop'],['project','item-edit']])
        output = self.run_command('start.sh','resume','org/repo','1',decode=False)
        self.assertIn('Status: existing_worktree', output)
        before = self.calls.read_text()
        output = self.run_command('status.sh','org/repo','1',decode=False)
        self.assertIn('org/4: Status=In progress', output)
        self.assertEqual(self.calls.read_text(), before)

    def test_public_start_does_not_update_boards_on_workspace_failure_and_can_retry(self):
        self.setup_repository()
        self.env['FAIL_DEVELOP'] = 'true'
        output = self.run_command('start.sh','start','org/repo','1',code=1,decode=False)
        self.assertNotIn('item-edit', self.calls.read_text())
        del self.env['FAIL_DEVELOP']
        self.run_command('start.sh','start','org/repo','1',decode=False)
        self.assertIn('item-edit', self.calls.read_text())

    def test_public_finish_reconciles_no_change_completion_and_closed_issue(self):
        self.setup_repository()
        self.run_command('start.sh','start','org/repo','1',decode=False)
        output = self.run_command('finish.sh','org/repo','1',decode=False)
        self.assertIn('closed as completed', output)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls[-2][:2], ['issue','close'])
        self.assertEqual(calls[-1][-1], 'done')
        # A subsequent finish repairs an external drift on the already completed issue.
        data = json.loads(self.fixture.read_text())
        value = data['data']['repository']['issue']['projectItems']['nodes'][0]['fieldValues']['nodes'][0]
        value.update(optionId='todo', name='Todo')
        self.fixture.write_text(json.dumps(data))
        self.run_command('finish.sh','org/repo','1',decode=False)
        self.assertEqual(json.loads(self.calls.read_text().splitlines()[-1])[-1], 'done')

    def test_public_finish_pr_readiness_and_closed_unmerged_pr_never_mark_done(self):
        self.setup_repository()
        output = self.run_command('start.sh','start','org/repo','1',decode=False)
        worktree = Path(next(line.split(': ',1)[1] for line in output.splitlines() if line.startswith('Worktree: ')))
        (worktree / 'change.txt').write_text('change')
        before = self.calls.read_text()
        output = self.run_command('finish.sh','org/repo','1',decode=False)
        self.assertIn('require review and validation', output)
        self.assertEqual(self.calls.read_text(), before)
        self.env['FAKE_PRS'] = '[{"state":"CLOSED","url":"https://example.invalid/pr","baseRefName":"main"}]'
        self.run_command('finish.sh','org/repo','1',code=2,decode=False)
        self.assertEqual(self.calls.read_text(), before)

    def test_tiers_merge_fields_disable_and_report_provenance(self):
        self.config.write_text(json.dumps({
            'schemaVersion': 2,
            'projectSync': {'boards': {'org/4': {'fields': {'Status': {'start': 'Active', 'complete': 'Done'}}}}},
            'organizations': {'ORG': {'projectSync': {'boards': {'Org/4': {'fields': {'status': {'start': 'Doing'}}}}}}},
            'repositories': {'Org/Repo': {'projectSync': {'boards': {'org/4': {'enabled': False}}}}}
        }))
        result = self.run_command('config.sh', 'org/repo')
        board = result['effective']['projectSync']['boards']['org/4']
        self.assertFalse(board['enabled'])
        self.assertEqual(board['fields']['status'], {'start': 'Doing', 'complete': 'Done'})
        self.assertEqual(result['sources']['projectSync.boards.org/4.fields.status.start'], 'organization:org')
        before = self.config.read_bytes()
        result = self.run_command('config.sh', 'ORG/REPO', '--override',
                                  '{"projectSync":{"boards":{"org/4":{"enabled":true}}}}')
        self.assertTrue(result['effective']['projectSync']['boards']['org/4']['enabled'])
        self.assertEqual(self.config.read_bytes(), before)

    def test_config_discovers_only_assigned_boards_and_saves_confirmed_preview(self):
        result = self.run_command('config.sh', 'org/repo', '--issue', '1', code=2)
        self.assertEqual(result['status'], 'needs_input')
        self.assertEqual([b['identity'] for b in result['boards']], ['org/4', 'org/5'])
        before = self.config.read_bytes()
        args = ['org/repo', '--issue', '1', '--scope', 'organization', '--set', json.dumps(self.mapping())]
        preview = self.run_command('config.sh', *args)
        self.assertEqual(preview['status'], 'preview')
        self.assertEqual(self.config.read_bytes(), before)
        saved = self.run_command('config.sh', *args, '--confirm', preview['token'])
        self.assertEqual(saved['status'], 'saved')
        self.assertIn('org', json.loads(self.config.read_text())['organizations'])
        self.assertFalse(self.calls.exists())
        result = self.run_command('config.sh', 'org/repo', '--issue', '1')
        self.assertEqual(result['status'], 'configured')

    def test_config_rejects_stale_preview_and_unassigned_board_selection(self):
        args = ['org/repo', '--issue', '1', '--set', json.dumps(self.mapping())]
        preview = self.run_command('config.sh', *args)
        self.config.write_text('{"worktreeManager":"git"}')
        result = self.run_command('config.sh', *args, '--confirm', preview['token'], code=2)
        self.assertEqual(result['status'], 'stale_preview')
        self.assertEqual(json.loads(self.config.read_text()), {'worktreeManager':'git'})
        result = self.run_command('config.sh', 'org/repo', '--issue', '1', '--set',
                                  '{"projectSync":{"boards":{"org/99":{"enabled":false}}}}', code=2)
        self.assertIn('not assigned', result['message'])

    def test_start_updates_only_assigned_managed_fields_with_canonical_ids(self):
        mapping = self.mapping()
        mapping['projectSync']['boards']['org/99'] = {'fields': {'Status': {'start':'Invalid'}}}
        self.config.write_text(json.dumps(mapping))
        preview = self.run_command('project-transition.sh', 'start', 'org/repo', '1', '--dry-run')
        self.assertFalse(self.calls.exists())
        self.assertEqual(len(preview['updates']), 1)
        result = self.run_command('project-transition.sh', 'start', 'org/repo', '1')
        self.assertEqual(result['updates'][0]['status'], 'updated')
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls, [['project','item-edit','--id','item-4','--project-id','project-4',
                                  '--field-id','field-4','--single-select-option-id','active']])
        again = self.run_command('project-transition.sh', 'start', 'org/repo', '1')
        self.assertEqual(again['updates'][0]['status'], 'unchanged')
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)

    def test_completion_requires_completed_issue_and_status_is_read_only(self):
        self.config.write_text(json.dumps(self.mapping()))
        result = self.run_command('project-transition.sh', 'complete', 'org/repo', '1', code=2)
        self.assertIn('completion', result['message'])
        data = self.github_issue()
        issue = data['data']['repository']['issue']
        issue.update(state='CLOSED', stateReason='NOT_PLANNED')
        self.fixture.write_text(json.dumps(data))
        self.run_command('project-transition.sh', 'complete', 'org/repo', '1', code=2)
        self.assertFalse(self.calls.exists())
        issue['stateReason'] = 'COMPLETED'
        self.fixture.write_text(json.dumps(data))
        result = self.run_command('project-transition.sh', 'status', 'org/repo', '1')
        self.assertEqual(result['updates'][0]['expected'], 'Done')
        self.assertFalse(self.calls.exists())
        result = self.run_command('project-transition.sh', 'complete', 'org/repo', '1')
        self.assertEqual(result['updates'][0]['expected'], 'Done')
        self.assertEqual(result['updates'][0]['status'], 'updated')

    def test_all_boards_validate_before_writes_and_partial_failures_are_retryable(self):
        mapping = self.mapping()
        mapping['projectSync']['boards']['org/5'] = {'fields':{'Delivery stage':{'start':'missing','complete':'Done'}}}
        self.config.write_text(json.dumps(mapping))
        self.run_command('project-transition.sh', 'start', 'org/repo', '1', code=2)
        self.assertFalse(self.calls.exists())
        mapping['projectSync']['boards']['org/5']['fields']['Delivery stage']['start'] = 'In progress'
        self.config.write_text(json.dumps(mapping))
        self.env['FAIL_ITEM'] = 'item-5'
        result = self.run_command('project-transition.sh', 'start', 'org/repo', '1', code=2)
        self.assertEqual([u['status'] for u in result['updates']], ['updated','failed'])
        del self.env['FAIL_ITEM']
        result = self.run_command('project-transition.sh', 'start', 'org/repo', '1')
        self.assertEqual([u['status'] for u in result['updates']], ['unchanged','updated'])

    def test_unknown_assigned_board_returns_setup_before_any_write(self):
        result = self.run_command('project-transition.sh', 'start', 'org/repo', '1', code=2)
        self.assertEqual(result['status'], 'needs_input')
        self.assertEqual(len(result['unresolved']), 2)
        self.assertFalse(self.calls.exists())


    def test_legacy_migration_preserves_owner_scope_and_unrelated_settings(self):
        original = {'worktreeManager':'git','customSetting':{'retain':True},
                    'projectStatus':{'enabled':True,'owner':'ORG','number':4,'field':'Status','startOption':'In Progress'},
                    'repositories':{'org/repo':{'taskBranchTemplate':'feat/task-{number}-{slug}'}}}
        self.config.write_text(json.dumps(original))
        result = self.run_command('config.sh','other/repo')
        self.assertEqual(result['effective']['projectSync']['boards'], {})
        result = self.run_command('config.sh','org/repo')
        self.assertEqual(result['effective']['projectSync']['boards']['org/4']['fields']['status'], {'start':'In Progress'})
        args = ['org/repo','--issue','1','--set',json.dumps(self.mapping())]
        preview = self.run_command('config.sh',*args)
        self.assertEqual(json.loads(self.config.read_text()), original)
        self.run_command('config.sh',*args,'--confirm',preview['token'])
        saved = json.loads(self.config.read_text())
        self.assertEqual(saved['customSetting'], {'retain':True})
        self.assertEqual(saved['repositories']['org/repo']['taskBranchTemplate'],'feat/task-{number}-{slug}')
        self.assertNotIn('projectStatus', saved)
        self.assertEqual(saved['schemaVersion'], 2)
        self.assertEqual(self.run_command('config.sh','other/repo')['effective']['projectSync']['boards'], {})

    def test_legacy_unnamed_rule_requires_explicit_assigned_board_choices(self):
        self.config.write_text(json.dumps({'repositories':{'org/repo':{
            'projectStatus':{'enabled':True,'field':'Status','startOption':'In Progress'}}}}))
        result = self.run_command('project-transition.sh','start','org/repo','1',code=2)
        self.assertEqual(result['status'],'needs_input')
        self.assertFalse(self.calls.exists())

    def test_case_collisions_and_incomplete_discovery_block_before_writes(self):
        self.config.write_text(json.dumps(self.mapping()))
        data = self.github_issue()
        fields = data['data']['repository']['issue']['projectItems']['nodes'][0]['project']['fields']
        fields['nodes'].append(dict(fields['nodes'][0],id='other-field',name='STATUS'))
        fields['totalCount'] = 2
        self.fixture.write_text(json.dumps(data))
        result = self.run_command('project-transition.sh','start','org/repo','1',code=2)
        self.assertEqual(result['status'],'needs_input')
        self.assertEqual(len(result['candidates']),2)
        mapping = self.mapping()
        mapping['projectSync']['boards']['org/4']['fields'] = {'id:field-4':{'start':'In progress','complete':'Done'}}
        self.config.write_text(json.dumps(mapping))
        self.run_command('project-transition.sh','start','org/repo','1','--dry-run')
        data['data']['repository']['issue']['projectItems']['totalCount'] = 3
        self.fixture.write_text(json.dumps(data))
        result = self.run_command('project-transition.sh','start','org/repo','1',code=2)
        self.assertIn('Incomplete', result['message'])
        self.assertFalse(self.calls.exists())

    def test_no_boards_disabled_sync_and_unmanaged_boards_do_not_write(self):
        data = self.github_issue()
        data['data']['repository']['issue']['projectItems'] = {'totalCount':0,'nodes':[]}
        self.fixture.write_text(json.dumps(data))
        self.assertEqual(self.run_command('project-transition.sh','start','org/repo','1')['updates'], [])
        self.fixture.write_text('invalid json')
        self.config.write_text('{"projectSync":{"enabled":false}}')
        self.assertEqual(self.run_command('project-transition.sh','start','org/repo','1')['status'], 'disabled')
        self.fixture.write_text(json.dumps(self.github_issue()))
        self.config.write_text('{"projectSync":{"boards":{"org/4":{"enabled":false},"org/5":{"enabled":false}}}}')
        self.assertEqual(self.run_command('project-transition.sh','start','org/repo','1')['updates'], [])
        self.assertFalse(self.calls.exists())

    def test_parent_uses_own_repository_settings_and_completion_stays_focused(self):
        data = self.github_issue()
        parent = self.github_issue()['data']['repository']['issue']
        parent.update(number=2,url='https://github.com/another/repo/issues/2',repository={'nameWithOwner':'another/repo'})
        for item in parent['projectItems']['nodes']:
            item['id'] = 'parent-' + item['id']
        data['data']['repository']['issue']['parent'] = parent
        self.fixture.write_text(json.dumps(data))
        mapping = self.mapping()
        mapping['repositories'] = {'another/repo':{'projectSync':{'boards':{'org/4':{'fields':{'Status':{'start':'Done'}}}}}}}
        self.config.write_text(json.dumps(mapping))
        result = self.run_command('project-transition.sh','start','org/repo','1','--dry-run')
        self.assertEqual([(u['repository'],u['expected']) for u in result['updates']], [('org/repo','In progress'),('another/repo','Done')])
        mapping['projectSync']['ancestors'] = False
        self.config.write_text(json.dumps(mapping))
        self.assertEqual(len(self.run_command('project-transition.sh','start','org/repo','1','--dry-run')['updates']),1)
        data['data']['repository']['issue'].update(state='CLOSED',stateReason='COMPLETED')
        self.fixture.write_text(json.dumps(data))
        self.assertEqual(len(self.run_command('project-transition.sh','complete','org/repo','1','--dry-run')['updates']),1)

    def test_default_provenance_and_invalid_legacy_configuration(self):
        result = self.run_command('config.sh','org/repo')
        self.assertEqual(result['sources']['projectSync.enabled'], 'default')
        for invalid in [{'projectStatus':'wrong'}, {'organizations':{'ORG':{},'org':{}}},
                        {'schemaVersion':99}, {'projectSync':{'boards':{'org/4':{'fields':{'Status':{'start':3}}}}}}]:
            self.config.write_text(json.dumps(invalid))
            self.assertEqual(self.run_command('config.sh','org/repo',code=2)['status'],'blocked')


    def test_legacy_repository_target_replaces_shared_target_without_extra_writes(self):
        self.config.write_text(json.dumps({
            'projectStatus':{'enabled':True,'owner':'org','number':4,'startOption':'In progress'},
            'repositories':{'org/repo':{'projectStatus':{'owner':'org','number':5,'field':'Delivery stage'}}}
        }))
        result = self.run_command('project-transition.sh','start','org/repo','1','--dry-run')
        self.assertEqual([u['board'] for u in result['updates']], ['org/5'])

    def test_public_start_setup_precedes_branch_mutation_and_override_is_ephemeral(self):
        self.setup_repository()
        mapping = json.loads(self.config.read_text())
        mapping['projectSync']['boards'] = {}
        self.config.write_text(json.dumps(mapping))
        result = self.run_command('start.sh','start','org/repo','1',code=2)
        self.assertEqual(result['status'],'needs_input')
        self.assertFalse(self.calls.exists())
        before = self.config.read_bytes()
        self.run_command('start.sh','start','--project-override',json.dumps(self.mapping()),'org/repo','1',decode=False)
        self.assertEqual(self.config.read_bytes(),before)

    def test_multiple_fields_same_board_and_option_ambiguity(self):
        data = self.github_issue()
        board = data['data']['repository']['issue']['projectItems']['nodes'][0]
        fields = board['project']['fields']
        fields['nodes'].append({'id':'phase','name':'Phase','options':[{'id':'build','name':'Build'},{'id':'ship','name':'Ship'}]})
        fields['totalCount'] = 2
        self.fixture.write_text(json.dumps(data))
        mapping = self.mapping()
        mapping['projectSync']['boards']['org/4']['fields']['Phase'] = {'start':'Build','complete':'Ship'}
        self.config.write_text(json.dumps(mapping))
        result = self.run_command('project-transition.sh','start','org/repo','1','--dry-run')
        self.assertEqual([u['fieldId'] for u in result['updates']],['field-4','phase'])
        fields['nodes'][0]['options'].append({'id':'ambiguous','name':'IN PROGRESS'})
        self.fixture.write_text(json.dumps(data))
        result = self.run_command('project-transition.sh','start','org/repo','1',code=2)
        self.assertEqual(result['status'],'needs_input')
        self.assertFalse(self.calls.exists())

    def test_config_can_disambiguate_an_inherited_field_without_adding_a_mapping(self):
        self.config.write_text(json.dumps(self.mapping()))
        data = self.github_issue()
        fields = data['data']['repository']['issue']['projectItems']['nodes'][0]['project']['fields']
        fields['nodes'].append(dict(fields['nodes'][0], id='other-field', name='STATUS'))
        fields['totalCount'] = 2
        self.fixture.write_text(json.dumps(data))
        patch = {'projectSync': {'boards': {'org/4': {'fields': {
            'Status': {'fieldId': 'field-4', 'start': 'id:active'}
        }}}}}
        args = ['org/repo', '--issue', '1', '--set', json.dumps(patch)]
        preview = self.run_command('config.sh', *args)
        self.run_command('config.sh', *args, '--confirm', preview['token'])
        result = self.run_command('project-transition.sh', 'start', 'org/repo', '1')
        self.assertEqual([u['fieldId'] for u in result['updates']], ['field-4'])
        effective = self.run_command('config.sh', 'org/repo')['effective']
        self.assertEqual(effective['projectSync']['boards']['org/4']['fields']['status']['complete'], 'done')

    def test_public_start_retry_after_partial_board_failure_reuses_workspace(self):
        self.setup_repository()
        mapping = json.loads(self.config.read_text())
        mapping['projectSync']['boards']['org/5'] = {'fields': {
            'Delivery stage': {'start': 'In progress', 'complete': 'Done'}
        }}
        self.config.write_text(json.dumps(mapping))
        self.env['FAIL_ITEM'] = 'item-5'
        self.run_command('start.sh', 'start', 'org/repo', '1', code=2, decode=False)
        del self.env['FAIL_ITEM']
        output = self.run_command('start.sh', 'resume', 'org/repo', '1', decode=False)
        self.assertIn('Status: existing_worktree', output)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(sum(call[:2] == ['issue', 'develop'] for call in calls), 1)
        edits = [call for call in calls if call[:2] == ['project', 'item-edit']]
        self.assertEqual([call[call.index('--id') + 1] for call in edits], ['item-4', 'item-5', 'item-5'])

    def test_config_lock_and_changed_discovery_preserve_saved_configuration(self):
        args = ['org/repo', '--issue', '1', '--set', json.dumps(self.mapping())]
        preview = self.run_command('config.sh', *args)
        before = self.config.read_bytes()
        lock = self.config.with_name('config.json.lock')
        lock.mkdir()
        self.run_command('config.sh', *args, '--confirm', preview['token'], code=2)
        self.assertEqual(self.config.read_bytes(), before)
        lock.rmdir()
        data = self.github_issue()
        data['data']['repository']['issue']['projectItems']['nodes'][0]['project']['title'] = 'Renamed board'
        self.fixture.write_text(json.dumps(data))
        result = self.run_command('config.sh', *args, '--confirm', preview['token'], code=2)
        self.assertEqual(result['status'], 'stale_preview')
        self.assertEqual(self.config.read_bytes(), before)

    def test_public_finish_missing_completion_mapping_preserves_open_issue(self):
        self.setup_repository()
        self.run_command('start.sh', 'start', 'org/repo', '1', decode=False)
        mapping = json.loads(self.config.read_text())
        mapping['projectSync']['boards']['org/4']['fields']['STATUS']['complete'] = 'Missing'
        self.config.write_text(json.dumps(mapping))
        before = self.calls.read_bytes()
        self.run_command('finish.sh', 'org/repo', '1', code=2, decode=False)
        self.assertEqual(self.calls.read_bytes(), before)
        self.assertEqual(json.loads(self.fixture.read_text())['data']['repository']['issue']['state'], 'OPEN')

    def test_public_finish_merged_pr_and_not_planned_closure(self):
        self.setup_repository()
        self.run_command('start.sh','start','org/repo','1',decode=False)
        self.env['FAKE_PRS'] = '[{"state":"MERGED","url":"https://example.invalid/pr","baseRefName":"main"}]'
        output = self.run_command('finish.sh','org/repo','1',decode=False)
        self.assertIn('closed as completed because',output)
        self.assertEqual(json.loads(self.calls.read_text().splitlines()[-1])[-1],'done')
        data = json.loads(self.fixture.read_text())
        data['data']['repository']['issue']['stateReason'] = 'NOT_PLANNED'
        self.fixture.write_text(json.dumps(data))
        before = self.calls.read_bytes()
        self.run_command('finish.sh','org/repo','1',decode=False)
        self.assertEqual(self.calls.read_bytes(),before)



if __name__ == '__main__':
    unittest.main()
