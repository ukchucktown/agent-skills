#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
start_command=$repository_root/skills/engineering/gh-issue/scripts/start.sh

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-start-tests.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

fake_bin=$temporary_directory/bin
mkdir -p "$fake_bin"
cat >"$fake_bin/gh" <<'EOF'
#!/bin/sh
set -eu

case "${1:-}:${2:-}" in
  api:graphql)
    number=
    for argument in "$@"; do
      case "$argument" in
        number=*) number=${argument#number=} ;;
      esac
    done
    case "$number" in
      101)
        linked='[]'
        total=0
        title='Create a scripted start workflow'
        ;;
      102)
        linked='[{"ref":{"name":"feat/issue-102-existing","repository":{"nameWithOwner":"example/start"}}}]'
        total=1
        title='Resume existing work'
        ;;
      103)
        linked='[{"ref":{"name":"feat/issue-103-one","repository":{"nameWithOwner":"example/start"}}},{"ref":{"name":"fix/issue-103-two","repository":{"nameWithOwner":"example/start"}}}]'
        total=2
        title='Resolve conflicting work'
        ;;
      104)
        linked='[]'
        total=0
        title='Create a Supacode worktree'
        ;;
      105)
        linked='[]'
        total=0
        title='Build the child task'
        parent='{"number":100,"title":"Build the platform","state":"OPEN","labels":{"nodes":[]},"linkedBranches":{"totalCount":0,"nodes":[]},"subIssues":{"totalCount":1,"nodes":[{"number":105}]},"parent":null}'
        ;;
      *) exit 70 ;;
    esac
    parent=${parent:-null}
    jq -cn \
      --argjson number "$number" \
      --arg title "$title" \
      --argjson linked "$linked" \
      --argjson total "$total" \
      --argjson parent "$parent" \
      '{data:{repository:{nameWithOwner:"example/start",defaultBranchRef:{name:"main"},issue:{number:$number,title:$title,state:"OPEN",labels:{nodes:[]},linkedBranches:{totalCount:$total,nodes:$linked},subIssues:{totalCount:0},parent:$parent}}}}'
    ;;
  issue:develop)
    issue_number=$3
    shift 3
    base=
    branch=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --base) base=$2; shift 2 ;;
        --name) branch=$2; shift 2 ;;
        --repo) shift 2 ;;
        *) shift ;;
      esac
    done
    printf 'issue develop %s --base %s --name %s\n' "$issue_number" "$base" "$branch" >>"$GH_CALL_LOG"
    if "$REAL_GIT" -C "$START_PRIMARY" rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
      "$REAL_GIT" -C "$START_PRIMARY" push -q origin "$base:refs/heads/$branch"
    else
      remote_url=$("$REAL_GIT" -C "$START_PRIMARY" remote get-url origin)
      base_oid=$("$REAL_GIT" --git-dir="$remote_url" rev-parse "refs/heads/$base")
      "$REAL_GIT" --git-dir="$remote_url" update-ref "refs/heads/$branch" "$base_oid"
    fi
    ;;
  *)
    printf 'unexpected gh call: %s\n' "$*" >&2
    exit 70
    ;;
esac
EOF
chmod +x "$fake_bin/gh"

cat >"$fake_bin/supacode" <<'EOF'
#!/bin/sh
set -eu

case "${1:-}:${2:-}" in
  repo:list)
    canonical_primary=$("$REAL_GIT" -C "$START_PRIMARY" rev-parse --show-toplevel)
    jq -nr --arg value "${canonical_primary%/}/" '$value | @uri'
    ;;
  repo:worktree-new)
    shift 2
    branch=
    base=
    location=
    name=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --branch) branch=$2; shift 2 ;;
        --base) base=$2; shift 2 ;;
        --location) location=$2; shift 2 ;;
        --name) name=$2; shift 2 ;;
        -r|--repo|--upstream) shift 2 ;;
        --background) shift ;;
        *) shift ;;
      esac
    done
    mkdir -p "$location"
    "$REAL_GIT" -C "$START_PRIMARY" worktree add -q -b "$branch" --track "$location/$name" "$base"
    jq -nr --arg value "${location%/}/$name/" '$value | @uri'
    ;;
  *)
    printf 'unexpected supacode call: %s\n' "$*" >&2
    exit 70
    ;;
esac
EOF
chmod +x "$fake_bin/supacode"

remote=$temporary_directory/remote.git
primary=$temporary_directory/start
git init -q --bare "$remote"
git init -q -b main "$primary"
git -C "$primary" config user.name Test
git -C "$primary" config user.email test@example.com
git -C "$primary" config "url.$remote.insteadOf" https://github.com/example/start.git
git -C "$primary" remote add origin https://github.com/example/start.git
printf 'base\n' >"$primary/base.txt"
git -C "$primary" add base.txt
git -C "$primary" commit -q -m 'Initial state'
git -C "$primary" push -q -u origin main

git -C "$primary" push -q origin main:refs/heads/feat/issue-102-existing

config_file=$temporary_directory/config.json
cat >"$config_file" <<EOF
{
  "worktreeManager": "git",
  "worktreeRoot": "$temporary_directory/worktrees",
  "projectStatus": {"enabled": false},
  "repositories": {}
}
EOF
call_log=$temporary_directory/gh-calls.log
: >"$call_log"

start_output=$(cd "$primary" && PATH="$fake_bin:$PATH" \
  REAL_GIT="$(command -v git)" \
  START_PRIMARY="$primary" \
  GH_CALL_LOG="$call_log" \
  AGENT_SKILLS_CONFIG="$config_file" \
  "$start_command" start example/start 101)

printf '%s\n' "$start_output" | grep -F 'Status: started' >/dev/null
printf '%s\n' "$start_output" | grep -F 'Branch: feat/issue-101-create-a-scripted-start-workflow' >/dev/null
created_worktree=$temporary_directory/worktrees/start/issue-101-create-a-scripted-start-workflow
[ "$(git -C "$created_worktree" branch --show-current)" = 'feat/issue-101-create-a-scripted-start-workflow' ]
grep -F 'issue develop 101 --base main --name feat/issue-101-create-a-scripted-start-workflow' "$call_log" >/dev/null

: >"$call_log"
existing_output=$(cd "$primary" && PATH="$fake_bin:$PATH" \
  REAL_GIT="$(command -v git)" \
  START_PRIMARY="$primary" \
  GH_CALL_LOG="$call_log" \
  AGENT_SKILLS_CONFIG="$config_file" \
  "$start_command" start example/start 102)

printf '%s\n' "$existing_output" | grep -F 'Status: already_started' >/dev/null
printf '%s\n' "$existing_output" | grep -F 'Branch: feat/issue-102-existing' >/dev/null
[ ! -d "$temporary_directory/worktrees/start/issue-102-resume-existing-work" ]
[ ! -s "$call_log" ]

resume_output=$(cd "$primary" && PATH="$fake_bin:$PATH" \
  REAL_GIT="$(command -v git)" \
  START_PRIMARY="$primary" \
  GH_CALL_LOG="$call_log" \
  AGENT_SKILLS_CONFIG="$config_file" \
  "$start_command" resume example/start 102)

printf '%s\n' "$resume_output" | grep -F 'Status: resumed' >/dev/null
resumed_worktree=$temporary_directory/worktrees/start/issue-102-resume-existing-work
[ "$(git -C "$resumed_worktree" branch --show-current)" = 'feat/issue-102-existing' ]
[ ! -s "$call_log" ]

: >"$call_log"
set +e
ambiguous_output=$(cd "$primary" && PATH="$fake_bin:$PATH" \
  REAL_GIT="$(command -v git)" \
  START_PRIMARY="$primary" \
  GH_CALL_LOG="$call_log" \
  AGENT_SKILLS_CONFIG="$config_file" \
  "$start_command" start example/start 103 2>&1)
ambiguous_status=$?
set -e

[ "$ambiguous_status" -eq 2 ]
printf '%s' "$ambiguous_output" | jq -e '
  .status == "needs_input" and
  .field == "branch" and
  .candidates == ["feat/issue-103-one", "fix/issue-103-two"]
' >/dev/null
[ ! -s "$call_log" ]
[ ! -d "$temporary_directory/worktrees/start/issue-103-resolve-conflicting-work" ]

supacode_config_file=$temporary_directory/supacode-config.json
cat >"$supacode_config_file" <<EOF
{
  "worktreeManager": "supacode",
  "worktreeRoot": "$temporary_directory/supacode-worktrees",
  "projectStatus": {"enabled": false},
  "repositories": {}
}
EOF
: >"$call_log"

supacode_output=$(cd "$primary" && PATH="$fake_bin:$PATH" \
  REAL_GIT="$(command -v git)" \
  START_PRIMARY="$primary" \
  GH_CALL_LOG="$call_log" \
  AGENT_SKILLS_CONFIG="$supacode_config_file" \
  "$start_command" start example/start 104)

printf '%s\n' "$supacode_output" | grep -F 'Status: started' >/dev/null
printf '%s\n' "$supacode_output" | grep -F 'Manager: supacode' >/dev/null
supacode_worktree=$temporary_directory/supacode-worktrees/start/issue-104-create-a-supacode-worktree
[ "$(git -C "$supacode_worktree" branch --show-current)" = 'feat/issue-104-create-a-supacode-worktree' ]

: >"$call_log"
compound_output=$(cd "$primary" && PATH="$fake_bin:$PATH" \
  REAL_GIT="$(command -v git)" \
  START_PRIMARY="$primary" \
  GH_CALL_LOG="$call_log" \
  AGENT_SKILLS_CONFIG="$config_file" \
  "$start_command" start example/start 105)

printf '%s\n' "$compound_output" | grep -F 'Status: started' >/dev/null
printf '%s\n' "$compound_output" | grep -F 'Hierarchy: #100 Build the platform > #105 Build the child task' >/dev/null
grep -F 'issue develop 100 --base main --name integration/issue-100-build-the-platform' "$call_log" >/dev/null
grep -F 'issue develop 105 --base integration/issue-100-build-the-platform --name feat/issue-105-build-the-child-task' "$call_log" >/dev/null
compound_worktree=$temporary_directory/worktrees/start/issue-105-build-the-child-task
[ "$(git -C "$compound_worktree" branch --show-current)" = 'feat/issue-105-build-the-child-task' ]

printf 'gh-issue start tests passed\n'
