#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
status_command=$repository_root/skills/engineering/gh-issue/scripts/status.sh
finish_command=$repository_root/skills/engineering/gh-issue/scripts/finish.sh
project_config_command=$repository_root/skills/engineering/gh-issue/scripts/project-config.sh
project_start_command=$repository_root/skills/engineering/gh-issue/scripts/project-start.sh
fixture_directory=$repository_root/tests/gh-issue/fixtures

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-tests.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

fake_bin=$temporary_directory/bin
mkdir -p "$fake_bin"
cat >"$fake_bin/gh" <<'EOF'
#!/bin/sh
set -eu

case "${1:-}:${2:-}" in
  api:graphql)
    mode=
    number=
    for argument in "$@"; do
      case "$argument" in
        query=@*project-status.graphql) mode=project-status ;;
        query=@*finish.graphql) mode=finish ;;
        query=@*status.graphql) mode=status ;;
        number=*) number=${argument#number=} ;;
      esac
    done
    [ -n "$mode" ] && [ -n "$number" ] || exit 70
    cat "$GH_FIXTURE_DIRECTORY/$mode-$number.json"
    ;;
  pr:list)
    printf '[]\n'
    ;;
  issue:close)
    printf '%s\n' "$*" >>"$GH_CALL_LOG"
    ;;
  project:field-list)
    printf '%s\n' "$*" >>"$GH_CALL_LOG"
    cat <<'JSON'
{"fields":[{"id":"status-field","name":"Status","type":"ProjectV2SingleSelectField","options":[{"id":"todo","name":"Todo"},{"id":"progress","name":"In Progress"},{"id":"done","name":"Done"}]}],"totalCount":1}
JSON
    ;;
  project:item-add|project:item-edit)
    printf '%s\n' "$*" >>"$GH_CALL_LOG"
    ;;
  *)
    printf 'unexpected gh call: %s\n' "$*" >&2
    exit 70
    ;;
esac
EOF
chmod +x "$fake_bin/gh"

config_file=$temporary_directory/config.json
cat >"$config_file" <<'EOF'
{
  "repositories": {
    "example/agent-skills": {
      "projectStatus": {
        "enabled": true,
        "field": "Status",
        "startOption": "In Progress"
      }
    }
  }
}
EOF
call_log=$temporary_directory/gh-calls.log
: >"$call_log"

primary=$temporary_directory/repository
issue_39=$temporary_directory/issue-39
issue_40=$temporary_directory/issue-40

git init -q -b main "$primary"
git -C "$primary" config user.name Test
git -C "$primary" config user.email test@example.com
git -C "$primary" remote add origin https://github.com/example/agent-skills.git
printf 'base\n' >"$primary/base.txt"
git -C "$primary" add base.txt
git -C "$primary" commit -q -m 'Initial state'
git -C "$primary" branch feat/issue-39-prerequisite

for path in one two three four five six seven; do
  printf '%s\n' "$path" >"$primary/$path.txt"
done
git -C "$primary" add .
git -C "$primary" commit -q -m 'Advance main'

git -C "$primary" worktree add -q "$issue_39" feat/issue-39-prerequisite
git -C "$primary" worktree add -q -b feat/issue-40-changed "$issue_40" main
printf 'issue change\n' >"$issue_40/change.txt"
git -C "$issue_40" add change.txt
git -C "$issue_40" commit -q -m 'Add issue change'

status_output=$(cd "$primary" && PATH="$fake_bin:$PATH" \
  GH_FIXTURE_DIRECTORY="$fixture_directory" \
  GH_CALL_LOG="$call_log" \
  AGENT_SKILLS_CONFIG="$config_file" \
  "$status_command" example/agent-skills 39)

printf '%s\n' "$status_output" | grep -F 'State: OPEN' >/dev/null
printf '%s\n' "$status_output" | grep -F 'Local worktrees:' >/dev/null
printf '%s\n' "$status_output" | grep -F '[feat/issue-39-prerequisite]' >/dev/null
printf '%s\n' "$status_output" | grep -F 'Project status: In Progress' >/dev/null
printf '%s\n' "$status_output" | grep -F 'Started: yes' >/dev/null
printf '%s\n' "$status_output" | grep -F 'Next: continue or finish issue #39' >/dev/null

tip_difference_count=$(git -C "$issue_39" diff --name-only main..HEAD -- | wc -l | tr -d ' ')
[ "$tip_difference_count" -eq 7 ]
git -C "$issue_39" diff --quiet main...HEAD --

finish_output=$(cd "$primary" && PATH="$fake_bin:$PATH" \
  GH_FIXTURE_DIRECTORY="$fixture_directory" \
  GH_CALL_LOG="$call_log" \
  "$finish_command" example/agent-skills 39)

printf '%s\n' "$finish_output" | grep -F 'Issue #39 closed as completed.' >/dev/null
printf '%s\n' "$finish_output" | grep -F 'No commit, push, or pull request is necessary.' >/dev/null
grep -F 'issue close 39 --repo example/agent-skills --reason completed' "$call_log" >/dev/null

: >"$call_log"
changed_output=$(cd "$primary" && PATH="$fake_bin:$PATH" \
  GH_FIXTURE_DIRECTORY="$fixture_directory" \
  GH_CALL_LOG="$call_log" \
  "$finish_command" example/agent-skills 40)

printf '%s\n' "$changed_output" | grep -F 'Issue #40 has changes that require review and validation.' >/dev/null
printf '%s\n' "$changed_output" | grep -F -- '- change.txt' >/dev/null
[ ! -s "$call_log" ]

shared_config_file=$temporary_directory/shared-config.json
cat >"$shared_config_file" <<'EOF'
{
  "projectStatus": {
    "enabled": true,
    "owner": "example",
    "number": 2,
    "field": "Status",
    "startOption": "In Progress"
  },
  "repositories": {}
}
EOF

shared_config=$(AGENT_SKILLS_CONFIG="$shared_config_file" \
  "$project_config_command" example/agent-skills)
printf '%s' "$shared_config" | jq -e '
  .enabled == true and .targeted == true and
  .owner == "example" and .number == 2
' >/dev/null

shared_status_output=$(cd "$primary" && PATH="$fake_bin:$PATH" \
  GH_FIXTURE_DIRECTORY="$fixture_directory" \
  GH_CALL_LOG="$call_log" \
  AGENT_SKILLS_CONFIG="$shared_config_file" \
  "$status_command" example/agent-skills 39)
printf '%s\n' "$shared_status_output" | grep -F \
  'Project status: not in project' >/dev/null

external_config=$(AGENT_SKILLS_CONFIG="$shared_config_file" \
  "$project_config_command" someone-else/repository)
printf '%s' "$external_config" | jq -e '.enabled == false' >/dev/null

disabled_config_file=$temporary_directory/disabled-config.json
cat >"$disabled_config_file" <<'EOF'
{
  "projectStatus": {
    "enabled": true,
    "owner": "example",
    "number": 2
  },
  "repositories": {
    "example/agent-skills": {
      "projectStatus": {
        "enabled": false
      }
    }
  }
}
EOF

disabled_config=$(AGENT_SKILLS_CONFIG="$disabled_config_file" \
  "$project_config_command" example/agent-skills)
printf '%s' "$disabled_config" | jq -e \
  '.enabled == false and .owner == "example" and .number == 2' >/dev/null

override_config_file=$temporary_directory/override-config.json
cat >"$override_config_file" <<'EOF'
{
  "projectStatus": {
    "enabled": true,
    "owner": "example",
    "number": 2
  },
  "repositories": {
    "someone-else/repository": {
      "projectStatus": {
        "enabled": true,
        "owner": "example",
        "number": 3,
        "field": "Workflow",
        "startOption": "Doing"
      }
    }
  }
}
EOF

override_config=$(AGENT_SKILLS_CONFIG="$override_config_file" \
  "$project_config_command" someone-else/repository)
printf '%s' "$override_config" | jq -e '
  .enabled == true and .targeted == true and
  .owner == "example" and .number == 3 and
  .field == "Workflow" and .startOption == "Doing"
' >/dev/null

: >"$call_log"
project_output=$(PATH="$fake_bin:$PATH" \
  GH_FIXTURE_DIRECTORY="$fixture_directory" \
  GH_CALL_LOG="$call_log" \
  AGENT_SKILLS_CONFIG="$shared_config_file" \
  "$project_start_command" example/agent-skills 50)

printf '%s\n' "$project_output" | grep -F \
  'Focused issue was already In Progress: false' >/dev/null
printf '%s\n' "$project_output" | grep -F 'Project items added: 1' >/dev/null
printf '%s\n' "$project_output" | grep -F 'Project statuses updated: 2' >/dev/null

field_line=$(grep -n '^project field-list ' "$call_log" | cut -d: -f1)
add_line=$(grep -n '^project item-add .*issues/50' "$call_log" | cut -d: -f1)
focus_edit_line=$(grep -n '^project item-edit .*issues/50' "$call_log" | cut -d: -f1)
parent_edit_line=$(grep -n '^project item-edit .*issues/49' "$call_log" | cut -d: -f1)
[ "$field_line" -lt "$add_line" ]
[ "$add_line" -lt "$focus_edit_line" ]
[ "$focus_edit_line" -lt "$parent_edit_line" ]
if grep -F 'issues/48' "$call_log" >/dev/null; then
  echo 'closed ancestor was updated' >&2
  exit 1
fi

: >"$call_log"
disabled_output=$(PATH="$fake_bin:$PATH" \
  GH_FIXTURE_DIRECTORY="$fixture_directory" \
  GH_CALL_LOG="$call_log" \
  AGENT_SKILLS_CONFIG="$disabled_config_file" \
  "$project_start_command" example/agent-skills 50)
printf '%s\n' "$disabled_output" | grep -F \
  'Project status synchronization: disabled' >/dev/null
[ ! -s "$call_log" ]

: >"$call_log"
external_output=$(PATH="$fake_bin:$PATH" \
  GH_FIXTURE_DIRECTORY="$fixture_directory" \
  GH_CALL_LOG="$call_log" \
  AGENT_SKILLS_CONFIG="$shared_config_file" \
  "$project_start_command" someone-else/repository 50)
printf '%s\n' "$external_output" | grep -F \
  'Project status synchronization: disabled' >/dev/null
[ ! -s "$call_log" ]

: >"$call_log"
legacy_output=$(PATH="$fake_bin:$PATH" \
  GH_FIXTURE_DIRECTORY="$fixture_directory" \
  GH_CALL_LOG="$call_log" \
  AGENT_SKILLS_CONFIG="$config_file" \
  "$project_start_command" example/agent-skills 39)
printf '%s\n' "$legacy_output" | grep -F \
  'Focused issue was already In Progress: true' >/dev/null
printf '%s\n' "$legacy_output" | grep -F 'Project items added: 0' >/dev/null
printf '%s\n' "$legacy_output" | grep -F 'Project statuses updated: 0' >/dev/null
[ ! -s "$call_log" ]

"$repository_root/tests/gh-issue/clean.sh"
"$repository_root/tests/gh-issue/cancel.sh"
"$repository_root/tests/gh-issue/repository-clean.sh"
"$repository_root/tests/gh-issue/start.sh"

printf 'gh-issue deterministic command tests passed\n'
