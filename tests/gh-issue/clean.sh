#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
clean_command=$repository_root/skills/engineering/gh-issue/scripts/clean.sh
fixture_directory=$repository_root/tests/gh-issue/fixtures
real_git=$(command -v git)

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-clean-tests.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

remote=$temporary_directory/remote.git
primary=$temporary_directory/repository
root_worktree=$temporary_directory/issue-60
child_worktree=$temporary_directory/issue-61
dirty_worktree=$temporary_directory/issue-62
unmerged_worktree=$temporary_directory/issue-63
open_pr_worktree=$temporary_directory/issue-64
protected_worktree=$temporary_directory/issue-65
active_worktree=$temporary_directory/issue-66
local_only_worktree=$temporary_directory/issue-70

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
  path=$2
  base=$3
  filename=$4
  "$real_git" -C "$primary" branch "$branch" "$base"
  "$real_git" -C "$primary" worktree add -q "$path" "$branch"
  printf '%s\n' "$branch" >"$path/$filename"
  "$real_git" -C "$path" add "$filename"
  "$real_git" -C "$path" commit -q -m "Add $filename"
}

create_worktree feat/issue-60-root "$root_worktree" main root.txt
create_worktree feat/issue-61-child "$child_worktree" feat/issue-60-root child.txt
create_worktree feat/issue-62-dirty "$dirty_worktree" main dirty.txt
create_worktree feat/issue-63-unmerged "$unmerged_worktree" main unmerged.txt
create_worktree feat/issue-64-open-pr "$open_pr_worktree" main open-pr.txt
create_worktree feat/issue-65-protected "$protected_worktree" main protected.txt
create_worktree feat/issue-66-active "$active_worktree" main active.txt
create_worktree feat/issue-70-local-only "$local_only_worktree" main local-only.txt

remote=$(CDPATH= cd -- "$remote" && pwd -P)
primary=$("$real_git" -C "$primary" rev-parse --show-toplevel)
root_worktree=$("$real_git" -C "$root_worktree" rev-parse --show-toplevel)
child_worktree=$("$real_git" -C "$child_worktree" rev-parse --show-toplevel)
dirty_worktree=$("$real_git" -C "$dirty_worktree" rev-parse --show-toplevel)
unmerged_worktree=$("$real_git" -C "$unmerged_worktree" rev-parse --show-toplevel)
open_pr_worktree=$("$real_git" -C "$open_pr_worktree" rev-parse --show-toplevel)
protected_worktree=$("$real_git" -C "$protected_worktree" rev-parse --show-toplevel)
active_worktree=$("$real_git" -C "$active_worktree" rev-parse --show-toplevel)
local_only_worktree=$("$real_git" -C "$local_only_worktree" rev-parse --show-toplevel)

"$real_git" -C "$primary" merge -q --no-ff feat/issue-61-child -m 'Merge completed effort'
"$real_git" -C "$primary" merge -q --no-ff feat/issue-62-dirty -m 'Merge dirty child'
"$real_git" -C "$primary" merge -q --no-ff feat/issue-64-open-pr -m 'Merge open PR child'
"$real_git" -C "$primary" merge -q --no-ff feat/issue-65-protected -m 'Merge protected child'
"$real_git" -C "$primary" merge -q --no-ff feat/issue-66-active -m 'Merge active child'
"$real_git" -C "$primary" merge -q --no-ff feat/issue-70-local-only -m 'Merge local-only effort'
"$real_git" -C "$primary" push -q -u origin main
"$real_git" -C "$primary" push -q origin \
  feat/issue-60-root \
  feat/issue-61-child \
  feat/issue-62-dirty \
  feat/issue-63-unmerged \
  feat/issue-64-open-pr \
  feat/issue-65-protected \
  feat/issue-66-active \
  feat/issue-70-local-only

printf 'uncommitted\n' >"$dirty_worktree/uncommitted.txt"
"$real_git" -C "$primary" worktree lock "$root_worktree" --reason supacode
"$real_git" -C "$primary" worktree lock "$active_worktree" --reason supacode

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
    mode=
    number=
    for argument in "$@"; do
      case "$argument" in
        query=@*clean-root.graphql) mode=clean-root ;;
        query=@*clean-tree.graphql) mode=clean-tree ;;
        number=*) number=${argument#number=} ;;
      esac
    done
    cat "$GH_FIXTURE_DIRECTORY/$mode-$number.json"
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
            [ "$branch" != "feat/issue-65-protected" ] || protected=true
            printf '%s\t%s\t%s\n' "$branch" "$oid" "$protected"
          done
        ;;
      *)
        encoded=${endpoint##*/}
        branch=$(printf '%s' "$encoded" | sed 's/%2F/\//g; s/%2f/\//g')
        oid=$("$REAL_GIT" --git-dir="$CLEAN_REMOTE" rev-parse "refs/heads/$branch")
        protected=false
        [ "$branch" != "feat/issue-65-protected" ] || protected=true
        printf '%s\t%s\n' "$oid" "$protected"
        ;;
    esac
    ;;
  pr:list)
    printf '[]\n'
    ;;
  *)
    printf 'unexpected gh call: %s\n' "$*" >&2
    exit 70
    ;;
esac
EOF
chmod +x "$fake_bin/gh"

supacode_id=$(jq -nr --arg value "${root_worktree%/}/" '$value | @uri')
active_supacode_id=$(jq -nr --arg value "${active_worktree%/}/" '$value | @uri')
cat >"$fake_bin/supacode" <<'EOF'
#!/bin/sh
set -eu

case "${1:-}:${2:-}:${3:-}" in
  worktree:list:*)
    focused=false
    for argument in "$@"; do
      [ "$argument" != "--focused" ] || focused=true
    done
    if [ "$focused" = "true" ]; then
      printf '%s\tunpinned\n' "$SUPACODE_FOCUSED_ID"
    else
      printf '%s\tunpinned\n' "$SUPACODE_TEST_ID"
      printf '%s\tunpinned\n' "$SUPACODE_FOCUSED_ID"
    fi
    ;;
  worktree:delete:*)
    "$REAL_GIT" -C "$CLEAN_PRIMARY" worktree unlock "$SUPACODE_TEST_PATH"
    "$REAL_GIT" -C "$CLEAN_PRIMARY" worktree remove "$SUPACODE_TEST_PATH"
    ;;
  *)
    printf 'unexpected supacode call: %s\n' "$*" >&2
    exit 70
    ;;
esac
EOF
chmod +x "$fake_bin/supacode"

run_clean() {
  PATH="$fake_bin:$PATH" \
  REAL_GIT="$real_git" \
  GH_FIXTURE_DIRECTORY="$fixture_directory" \
  CLEAN_REMOTE="$remote" \
  CLEAN_PRIMARY="$primary" \
  SUPACODE_TEST_ID="$supacode_id" \
  SUPACODE_FOCUSED_ID="$active_supacode_id" \
  SUPACODE_TEST_PATH="$root_worktree" \
  "$clean_command" "$@"
}

plan_output=$(cd "$primary" && run_clean example/agent-skills 61)
printf '%s\n' "$plan_output" | grep -F \
  'Clean plan: issue #61 resolves to #60 Completed effort' >/dev/null
printf '%s\n' "$plan_output" | grep -F "$root_worktree [feat/issue-60-root] via supacode" >/dev/null
printf '%s\n' "$plan_output" | grep -F "$child_worktree [feat/issue-61-child] via git" >/dev/null
printf '%s\n' "$plan_output" | grep -F \
  'feat/issue-62-dirty: worktree is dirty or unavailable' >/dev/null
printf '%s\n' "$plan_output" | grep -F \
  'feat/issue-63-unmerged: branch tip is not verified in main' >/dev/null
printf '%s\n' "$plan_output" | grep -F \
  'feat/issue-64-open-pr: open pull request' >/dev/null
printf '%s\n' "$plan_output" | grep -F \
  'feat/issue-65-protected: remote branch is protected' >/dev/null
printf '%s\n' "$plan_output" | grep -F \
  'feat/issue-66-active: worktree is active in Supacode' >/dev/null

[ -d "$root_worktree" ]
[ -d "$child_worktree" ]
"$real_git" -C "$primary" show-ref --verify --quiet refs/heads/feat/issue-60-root
"$real_git" --git-dir="$remote" show-ref --verify --quiet refs/heads/feat/issue-60-root

if unmerged_output=$(cd "$primary" && run_clean example/agent-skills 63 2>&1); then
  echo 'cleanup accepted an unmerged top-level effort' >&2
  exit 1
fi
printf '%s\n' "$unmerged_output" | grep -F \
  'top-level effort #63 has not reached main' >/dev/null

token=$(printf '%s\n' "$plan_output" | awk '/^Confirmation token:/ { print $3 }')
printf 'became dirty\n' >"$child_worktree/stale.txt"
if (cd "$primary" && run_clean --confirm "$token" example/agent-skills 61 >/dev/null 2>&1); then
  echo 'stale cleanup plan was accepted' >&2
  exit 1
fi
[ -d "$root_worktree" ]
[ -d "$child_worktree" ]
unlink "$child_worktree/stale.txt"

plan_output=$(cd "$primary" && run_clean example/agent-skills 61)
token=$(printf '%s\n' "$plan_output" | awk '/^Confirmation token:/ { print $3 }')
apply_output=$(cd "$primary" && run_clean --confirm "$token" example/agent-skills 61)
printf '%s\n' "$apply_output" | grep -F \
  'Confirmed cleanup plan summary' >/dev/null
printf '%s\n' "$apply_output" | grep -F \
  'Worktrees to remove: 2' >/dev/null
printf '%s\n' "$apply_output" | grep -F \
  'Cleanup applied: 2 worktree(s), 2 local branch(es), 2 remote branch(es).' >/dev/null
if printf '%s\n' "$apply_output" | grep -F "$root_worktree" >/dev/null; then
  echo 'cleanup confirmation repeated worktree paths' >&2
  exit 1
fi
if printf '%s\n' "$apply_output" | grep -F 'feat/issue-60-root at ' >/dev/null; then
  echo 'cleanup confirmation repeated branch details' >&2
  exit 1
fi

[ ! -d "$root_worktree" ]
[ ! -d "$child_worktree" ]
if "$real_git" -C "$primary" show-ref --verify --quiet refs/heads/feat/issue-60-root; then
  echo 'eligible local root branch remains' >&2
  exit 1
fi
if "$real_git" --git-dir="$remote" show-ref --verify --quiet refs/heads/feat/issue-60-root; then
  echo 'eligible remote root branch remains' >&2
  exit 1
fi
[ -d "$dirty_worktree" ]
[ -d "$unmerged_worktree" ]
[ -d "$open_pr_worktree" ]
[ -d "$protected_worktree" ]
[ -d "$active_worktree" ]

if (cd "$unmerged_worktree" && run_clean example/agent-skills 61 >/dev/null 2>&1); then
  echo 'cleanup ran outside the primary stable checkout' >&2
  exit 1
fi

local_plan=$(cd "$primary" && run_clean --local-only example/agent-skills 70)
printf '%s\n' "$local_plan" | grep -F 'Remote branches to remove: 0' >/dev/null
printf '%s\n' "$local_plan" | grep -F \
  'remote branch preserved by --local-only' >/dev/null
local_token=$(printf '%s\n' "$local_plan" | awk '/^Confirmation token:/ { print $3 }')
local_apply=$(cd "$primary" && run_clean --local-only --confirm "$local_token" example/agent-skills 70)
printf '%s\n' "$local_apply" | grep -F \
  'Cleanup applied: 1 worktree(s), 1 local branch(es), 0 remote branch(es).' >/dev/null
[ ! -d "$local_only_worktree" ]
"$real_git" --git-dir="$remote" show-ref --verify --quiet refs/heads/feat/issue-70-local-only

printf 'gh-issue clean command tests passed\n'
