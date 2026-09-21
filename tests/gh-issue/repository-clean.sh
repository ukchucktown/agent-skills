#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
clean_command=$repository_root/skills/engineering/gh-issue/scripts/clean.sh
fixture=$repository_root/tests/gh-issue/fixtures/clean-repository.json
real_git=$(command -v git)

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-repository-clean-tests.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

remote=$temporary_directory/remote.git
primary=$temporary_directory/repository
leftover_worktree=$temporary_directory/leftover
active_worktree=$temporary_directory/active
protected_worktree=$temporary_directory/protected
open_pr_worktree=$temporary_directory/open-pr
unselected_worktree=$temporary_directory/unselected
locked_worktree=$temporary_directory/locked
orphan_both_worktree=$temporary_directory/orphan-both
orphan_local_worktree=$temporary_directory/orphan-local
orphan_remote_worktree=$temporary_directory/orphan-remote

"$real_git" init -q --bare "$remote"
"$real_git" init -q -b main "$primary"
"$real_git" -C "$primary" config user.name Test
"$real_git" -C "$primary" config user.email test@example.com
"$real_git" -C "$primary" remote add origin "$remote"
printf 'base\n' >"$primary/base.txt"
"$real_git" -C "$primary" add base.txt
"$real_git" -C "$primary" commit -q -m 'Initial state'

create_worktree() {
  branch=$1
  worktree=$2
  filename=$3
  "$real_git" -C "$primary" worktree add -q -b "$branch" "$worktree" main
  printf '%s\n' "$branch" >"$worktree/$filename"
  "$real_git" -C "$worktree" add "$filename"
  "$real_git" -C "$worktree" commit -q -m "Add $filename"
}

create_worktree feat/leftover "$leftover_worktree" leftover.txt
create_worktree feat/active "$active_worktree" active.txt
create_worktree feat/protected "$protected_worktree" protected.txt
create_worktree feat/open-pr "$open_pr_worktree" open-pr.txt
create_worktree feat/unselected "$unselected_worktree" unselected.txt
create_worktree feat/locked "$locked_worktree" locked.txt
create_worktree feat/orphan-both "$orphan_both_worktree" orphan-both.txt
create_worktree feat/orphan-local "$orphan_local_worktree" orphan-local.txt
create_worktree feat/orphan-remote "$orphan_remote_worktree" orphan-remote.txt

for branch in feat/unselected feat/orphan-both feat/orphan-local feat/orphan-remote; do
  "$real_git" -C "$primary" merge -q --no-ff "$branch" -m "Merge $branch"
done

"$real_git" -C "$primary" push -q -u origin main
"$real_git" -C "$primary" push -q origin \
  feat/leftover feat/active feat/protected feat/open-pr feat/unselected feat/locked
"$real_git" -C "$primary" push -q origin feat/orphan-both feat/orphan-remote

"$real_git" -C "$primary" worktree remove "$orphan_both_worktree"
"$real_git" -C "$primary" worktree remove "$orphan_local_worktree"
"$real_git" -C "$primary" worktree remove "$orphan_remote_worktree"
"$real_git" -C "$primary" branch -D feat/orphan-remote >/dev/null

printf 'diverge\n' >>"$leftover_worktree/leftover.txt"
"$real_git" -C "$leftover_worktree" add leftover.txt
"$real_git" -C "$leftover_worktree" commit -q -m 'Diverge locally'
printf 'uncommitted\n' >"$leftover_worktree/uncommitted.txt"
"$real_git" -C "$primary" worktree lock "$active_worktree" --reason supacode
"$real_git" -C "$primary" worktree lock "$locked_worktree" --reason other

remote=$(CDPATH= cd -- "$remote" && pwd -P)
primary=$("$real_git" -C "$primary" rev-parse --show-toplevel)
leftover_worktree=$("$real_git" -C "$leftover_worktree" rev-parse --show-toplevel)
active_worktree=$("$real_git" -C "$active_worktree" rev-parse --show-toplevel)
protected_worktree=$("$real_git" -C "$protected_worktree" rev-parse --show-toplevel)
open_pr_worktree=$("$real_git" -C "$open_pr_worktree" rev-parse --show-toplevel)
unselected_worktree=$("$real_git" -C "$unselected_worktree" rev-parse --show-toplevel)
locked_worktree=$("$real_git" -C "$locked_worktree" rev-parse --show-toplevel)

fake_bin=$temporary_directory/bin
mkdir -p "$fake_bin"

cat >"$fake_bin/git" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = "remote" ] && [ "${2:-}" = "get-url" ] && [ "${3:-}" = "origin" ]; then
  printf 'https://github.com/example/agent-skills.git\n'
  exit 0
fi
exec "$REAL_GIT" "$@"
EOF
chmod +x "$fake_bin/git"

cat >"$fake_bin/gh" <<'EOF'
#!/bin/sh
set -eu

case "${1:-}:${2:-}" in
  api:graphql)
    cat "$CLEAN_REPOSITORY_FIXTURE"
    ;;
  api:*)
    endpoint=
    for argument in "$@"; do
      case "$argument" in
        repos/*/branches*) endpoint=$argument ;;
      esac
    done
    case "$endpoint" in
      *\?*)
        "$REAL_GIT" --git-dir="$CLEAN_REMOTE" for-each-ref \
          --format='%(refname:strip=2)%09%(objectname)' refs/heads |
          while IFS="$(printf '\t')" read -r branch oid; do
            protected=false
            [ "$branch" != "feat/protected" ] || protected=true
            printf '%s\t%s\t%s\n' "$branch" "$oid" "$protected"
          done
        ;;
      *)
        encoded=${endpoint##*/}
        branch=$(printf '%s' "$encoded" | sed 's/%2F/\//g; s/%2f/\//g')
        oid=$("$REAL_GIT" --git-dir="$CLEAN_REMOTE" rev-parse "refs/heads/$branch")
        protected=false
        [ "$branch" != "feat/protected" ] || protected=true
        printf '%s\t%s\n' "$oid" "$protected"
        ;;
    esac
    ;;
  issue:*|pr:*)
    printf '%s\n' "$*" >>"$GH_CALL_LOG"
    exit 70
    ;;
  *)
    printf 'unexpected gh call: %s\n' "$*" >&2
    exit 70
    ;;
esac
EOF
chmod +x "$fake_bin/gh"

active_supacode_id=$(jq -nr --arg value "${active_worktree%/}/" '$value | @uri')
cat >"$fake_bin/supacode" <<'EOF'
#!/bin/sh
set -eu

case "${1:-}:${2:-}:${3:-}" in
  worktree:list:*)
    printf '%s\tunpinned\n' "$SUPACODE_ACTIVE_ID"
    ;;
  worktree:delete:*)
    id=
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--worktree" ]; then
        id=$2
        break
      fi
      shift
    done
    [ "$id" = "$SUPACODE_ACTIVE_ID" ] || exit 70
    "$REAL_GIT" -C "$CLEAN_PRIMARY" worktree unlock "$SUPACODE_ACTIVE_PATH"
    "$REAL_GIT" -C "$CLEAN_PRIMARY" worktree remove --force "$SUPACODE_ACTIVE_PATH"
    ;;
  *)
    printf 'unexpected supacode call: %s\n' "$*" >&2
    exit 70
    ;;
esac
EOF
chmod +x "$fake_bin/supacode"

call_log=$temporary_directory/gh-calls.log
: >"$call_log"

run_clean() {
  PATH="$fake_bin:$PATH" \
  REAL_GIT="$real_git" \
  CLEAN_REPOSITORY_FIXTURE="$fixture" \
  CLEAN_REMOTE="$remote" \
  CLEAN_PRIMARY="$primary" \
  GH_CALL_LOG="$call_log" \
  SUPACODE_ACTIVE_ID="$active_supacode_id" \
  SUPACODE_ACTIVE_PATH="$active_worktree" \
  "$clean_command" "$@"
}

candidate_output=$(cd "$primary" && run_clean example/agent-skills)
printf '%s\n' "$candidate_output" | grep -F 'Repository cleanup candidates' >/dev/null
printf '%s\n' "$candidate_output" | grep -F 'Selectable groups: 4' >/dev/null
printf '%s\n' "$candidate_output" | grep -F 'Blocked groups: 5' >/dev/null
printf '%s\n' "$candidate_output" | grep -F \
  'Choose all selectable groups, comma-separated numbers or ranges, or exact branch names' >/dev/null
printf '%s\n' "$candidate_output" | grep -F \
  'feat/leftover' | grep -F \
  'worktree has uncommitted changes; local and remote tips differ; branch tip is not in main' >/dev/null
printf '%s\n' "$candidate_output" | grep -F \
  'feat/active' | grep -F \
  'worktree is active in Supacode; branch tip is not in main' >/dev/null
printf '%s\n' "$candidate_output" | grep -F \
  'feat/protected' | grep -F 'remote branch is protected' >/dev/null
printf '%s\n' "$candidate_output" | grep -F \
  'feat/open-pr' | grep -F 'open pull request' >/dev/null
printf '%s\n' "$candidate_output" | grep -F \
  'feat/locked' | grep -F 'locked outside Supacode' >/dev/null
for branch in feat/orphan-both feat/orphan-local feat/orphan-remote; do
  printf '%s\n' "$candidate_output" | grep -F "$branch" | grep -F 'no worktree' >/dev/null
done
[ ! -s "$call_log" ]
[ -d "$leftover_worktree" ]
[ -d "$active_worktree" ]

all_plan_output=$(cd "$primary" && run_clean --all example/agent-skills)
printf '%s\n' "$all_plan_output" | grep -F 'Risk policy: safe only' >/dev/null
printf '%s\n' "$all_plan_output" | grep -F 'Selected groups: 4' >/dev/null
printf '%s\n' "$all_plan_output" | grep -F 'Worktrees to remove: 1' >/dev/null
printf '%s\n' "$all_plan_output" | grep -F 'Local branches to remove: 3' >/dev/null
printf '%s\n' "$all_plan_output" | grep -F 'Remote branches to remove: 3' >/dev/null
printf '%s\n' "$all_plan_output" | grep -F 'Unselected selectable groups: 0' >/dev/null
for branch in feat/unselected feat/orphan-both feat/orphan-local feat/orphan-remote; do
  printf '%s\n' "$all_plan_output" | grep -F -- "- $branch" >/dev/null
done
if (cd "$primary" && run_clean --all --select feat/leftover example/agent-skills >/dev/null 2>&1); then
  echo 'repository cleanup accepted --all with --select' >&2
  exit 1
fi

if blocked_output=$(cd "$primary" && run_clean --select feat/protected example/agent-skills 2>&1); then
  echo 'repository cleanup accepted a protected branch' >&2
  exit 1
fi
printf '%s\n' "$blocked_output" | grep -F \
  'branch feat/protected cannot be selected: remote branch is protected' >/dev/null

safe_token=$(printf '%s\n' "$all_plan_output" | awk '/^Confirmation token:/ { print $3 }')
safe_apply_output=$(cd "$primary" && run_clean \
  --all --confirm "$safe_token" example/agent-skills)
printf '%s\n' "$safe_apply_output" | grep -F \
  'Repository cleanup applied: 1 worktree(s), 3 local branch(es), 3 remote branch(es).' >/dev/null
[ ! -d "$unselected_worktree" ]
if "$real_git" -C "$primary" show-ref --verify --quiet refs/heads/feat/unselected; then
  echo 'repository cleanup --all left the local branch' >&2
  exit 1
fi
if "$real_git" --git-dir="$remote" show-ref --verify --quiet refs/heads/feat/unselected; then
  echo 'repository cleanup --all left the remote branch' >&2
  exit 1
fi
for branch in feat/orphan-both feat/orphan-local; do
  if "$real_git" -C "$primary" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "repository cleanup --all left local branch $branch" >&2
    exit 1
  fi
done
for branch in feat/orphan-both feat/orphan-remote; do
  if "$real_git" --git-dir="$remote" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "repository cleanup --all left remote branch $branch" >&2
    exit 1
  fi
done

force_output=$(cd "$primary" && run_clean --force example/agent-skills)
printf '%s\n' "$force_output" | grep -F 'Selectable groups: 2' >/dev/null
printf '%s\n' "$force_output" | grep -F 'Blocked groups: 3' >/dev/null
printf '%s\n' "$force_output" | grep -F 'feat/leftover' | grep -F \
  'warnings: worktree has uncommitted changes; local and remote tips differ; branch tip is not in main' >/dev/null
printf '%s\n' "$force_output" | grep -F 'feat/active' | grep -F \
  'warnings: worktree is active in Supacode; branch tip is not in main' >/dev/null

force_plan=$(cd "$primary" && run_clean --force --all example/agent-skills)
printf '%s\n' "$force_plan" | grep -F 'Risk policy: force' >/dev/null
printf '%s\n' "$force_plan" | grep -F 'Selected groups: 2' >/dev/null
force_token=$(printf '%s\n' "$force_plan" | awk '/^Confirmation token:/ { print $3 }')
printf 'stale\n' >>"$leftover_worktree/leftover.txt"
"$real_git" -C "$leftover_worktree" add leftover.txt
"$real_git" -C "$leftover_worktree" commit -q -m 'Change selected branch'
if (cd "$primary" && run_clean \
  --force --all --confirm "$force_token" example/agent-skills >/dev/null 2>&1); then
  echo 'stale forced repository cleanup plan was accepted' >&2
  exit 1
fi
[ -d "$leftover_worktree" ]
[ -d "$active_worktree" ]

force_plan=$(cd "$primary" && run_clean --force --all example/agent-skills)
force_token=$(printf '%s\n' "$force_plan" | awk '/^Confirmation token:/ { print $3 }')
force_apply_output=$(cd "$primary" && run_clean \
  --force --all --confirm "$force_token" example/agent-skills)
printf '%s\n' "$force_apply_output" | grep -F \
  'Repository cleanup applied: 2 worktree(s), 2 local branch(es), 2 remote branch(es).' >/dev/null
[ ! -d "$leftover_worktree" ]
[ ! -d "$active_worktree" ]
for branch in feat/leftover feat/active; do
  if "$real_git" -C "$primary" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "forced repository cleanup left local branch $branch" >&2
    exit 1
  fi
  if "$real_git" --git-dir="$remote" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "forced repository cleanup left remote branch $branch" >&2
    exit 1
  fi
done

for worktree in "$protected_worktree" "$open_pr_worktree" "$locked_worktree"; do
  [ -d "$worktree" ]
done
for branch in feat/protected feat/open-pr feat/locked; do
  "$real_git" -C "$primary" show-ref --verify --quiet "refs/heads/$branch"
  "$real_git" --git-dir="$remote" show-ref --verify --quiet "refs/heads/$branch"
done
[ ! -s "$call_log" ]

printf 'gh-issue repository clean command tests passed\n'
