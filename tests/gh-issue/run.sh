#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
status_command=$repository_root/skills/engineering/gh-issue/scripts/status.sh
finish_command=$repository_root/skills/engineering/gh-issue/scripts/finish.sh
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
  *)
    printf 'unexpected gh call: %s\n' "$*" >&2
    exit 70
    ;;
esac
EOF
chmod +x "$fake_bin/gh"

config_file=$temporary_directory/config.json
printf '%s\n' '{"projectSync":{"enabled":false},"repositories":{}}' >"$config_file"
export AGENT_SKILLS_CONFIG="$config_file"
call_log=$temporary_directory/gh-calls.log
: >"$call_log"

export REAL_GIT="$(command -v git)"
cat >"$fake_bin/git" <<'GIT'
#!/bin/sh
if [ "$1" = remote ] && [ "$2" = get-url ]; then
  printf 'https://github.com/example/agent-skills.git\n'
else
  exec "$REAL_GIT" "$@"
fi
GIT
chmod +x "$fake_bin/git"
remote=$temporary_directory/remote.git
git init -q --bare "$remote"
primary=$temporary_directory/repository
issue_39=$temporary_directory/issue-39
issue_40=$temporary_directory/issue-40

git init -q -b main "$primary"
git -C "$primary" config user.name Test
git -C "$primary" config user.email test@example.com
git -C "$primary" config "url.$remote.insteadOf" https://github.com/example/agent-skills.git
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
git -C "$primary" push -qu origin main

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
printf '%s\n' "$status_output" | grep -F 'Project status: disabled' >/dev/null
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

# Both commands honor a repository's single task base.
git -C "$primary" branch task-integration main
jq '.repositories["example/agent-skills"].taskBaseBranch = "task-integration"' "$config_file" >"$config_file.next"
mv "$config_file.next" "$config_file"
configured_finish=$(cd "$primary" && PATH="$fake_bin:$PATH" \
  GH_FIXTURE_DIRECTORY="$fixture_directory" GH_CALL_LOG="$call_log" \
  "$finish_command" example/agent-skills 40)
printf '%s\n' "$configured_finish" | grep -Fx 'Base: task-integration' >/dev/null
explicit_finish=$(cd "$primary" && PATH="$fake_bin:$PATH" \
  GH_FIXTURE_DIRECTORY="$fixture_directory" GH_CALL_LOG="$call_log" \
  "$finish_command" --base main example/agent-skills 40)
printf '%s\n' "$explicit_finish" | grep -Fx 'Base: main' >/dev/null

"$repository_root/tests/gh-issue/clean.sh"
"$repository_root/tests/gh-issue/cancel.sh"
"$repository_root/tests/gh-issue/repository-clean.sh"
"$repository_root/tests/gh-issue/start.sh"
"$repository_root/tests/gh-issue/finish-worktree.sh"
"$repository_root/tests/gh-issue/finish-remote.sh"
"$repository_root/tests/gh-issue/status-recommendation.sh"

python3 "$repository_root/tests/gh-issue/projects.py"

printf 'gh-issue deterministic command tests passed\n'
