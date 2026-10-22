#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
clean_command=$repository_root/skills/engineering/gh-issue/scripts/clean.sh
fixture_directory=$repository_root/tests/gh-issue/fixtures
fake_graphql=$repository_root/tests/gh-issue/fake-graphql.sh
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
open_effort_worktree=$temporary_directory/issue-67
open_task_worktree=$temporary_directory/issue-68
local_only_worktree=$temporary_directory/issue-70
open_other_worktree=$temporary_directory/issue-75

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
create_worktree feat/issue-67-open-effort "$open_effort_worktree" main open-effort.txt
create_worktree feat/issue-68-merged-task "$open_task_worktree" main open-task.txt
create_worktree feat/issue-70-local-only "$local_only_worktree" main local-only.txt
create_worktree feat/issue-75-port-62-fixes "$open_other_worktree" main port.txt
"$real_git" -C "$primary" branch feat/issue-404-not-an-issue main
"$real_git" -C "$primary" branch feat/issue-73-foreign-parent main

remote=$(CDPATH= cd -- "$remote" && pwd -P)
primary=$("$real_git" -C "$primary" rev-parse --show-toplevel)
root_worktree=$("$real_git" -C "$root_worktree" rev-parse --show-toplevel)
child_worktree=$("$real_git" -C "$child_worktree" rev-parse --show-toplevel)
dirty_worktree=$("$real_git" -C "$dirty_worktree" rev-parse --show-toplevel)
unmerged_worktree=$("$real_git" -C "$unmerged_worktree" rev-parse --show-toplevel)
open_pr_worktree=$("$real_git" -C "$open_pr_worktree" rev-parse --show-toplevel)
protected_worktree=$("$real_git" -C "$protected_worktree" rev-parse --show-toplevel)
active_worktree=$("$real_git" -C "$active_worktree" rev-parse --show-toplevel)
open_effort_worktree=$("$real_git" -C "$open_effort_worktree" rev-parse --show-toplevel)
open_task_worktree=$("$real_git" -C "$open_task_worktree" rev-parse --show-toplevel)
local_only_worktree=$("$real_git" -C "$local_only_worktree" rev-parse --show-toplevel)
open_other_worktree=$("$real_git" -C "$open_other_worktree" rev-parse --show-toplevel)

"$real_git" -C "$primary" merge -q --no-ff feat/issue-61-child -m 'Merge completed effort'
"$real_git" -C "$primary" merge -q --no-ff feat/issue-62-dirty -m 'Merge dirty child'
"$real_git" -C "$primary" merge -q --no-ff feat/issue-64-open-pr -m 'Merge open PR child'
"$real_git" -C "$primary" merge -q --no-ff feat/issue-65-protected -m 'Merge protected child'
"$real_git" -C "$primary" merge -q --no-ff feat/issue-66-active -m 'Merge active child'
"$real_git" -C "$primary" merge -q --no-ff feat/issue-67-open-effort -m 'Merge open effort'
"$real_git" -C "$primary" merge -q --no-ff feat/issue-68-merged-task -m 'Merge task in open effort'
"$real_git" -C "$primary" merge -q --no-ff feat/issue-70-local-only -m 'Merge local-only effort'
"$real_git" -C "$primary" merge -q --no-ff feat/issue-75-port-62-fixes -m 'Merge open issue'
"$real_git" -C "$primary" push -q -u origin main
"$real_git" -C "$primary" push -q origin \
  feat/issue-60-root \
  feat/issue-61-child \
  feat/issue-62-dirty \
  feat/issue-63-unmerged \
  feat/issue-64-open-pr \
  feat/issue-65-protected \
  feat/issue-66-active \
  feat/issue-67-open-effort \
  feat/issue-68-merged-task \
  feat/issue-70-local-only \
  feat/issue-73-foreign-parent \
  feat/issue-75-port-62-fixes \
  feat/issue-404-not-an-issue

printf 'uncommitted\n' >"$dirty_worktree/uncommitted.txt"
"$real_git" -C "$primary" worktree lock "$active_worktree" --reason reserved

fake_bin=$temporary_directory/bin
mkdir -p "$fake_bin"

# Record any retired integration call without access to the real installation.
cat >"$fake_bin/supacode" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$(dirname -- "$0")/supacode-calls"
exit 70
EOF
chmod +x "$fake_bin/supacode"

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
    exec "$GH_FAKE_GRAPHQL" "$@"
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

run_clean() {
  PATH="$fake_bin:$PATH" \
  REAL_GIT="$real_git" \
  GH_FAKE_GRAPHQL="$fake_graphql" \
  GH_ISSUE_GRAPH="$fixture_directory/clean-graph.json" \
  CLEAN_REMOTE="$remote" \
  CLEAN_PRIMARY="$primary" \
  "$clean_command" "$@"
}

plan_output=$(cd "$primary" && run_clean example/agent-skills 60)
printf '%s\n' "$plan_output" | grep -F \
  'Clean plan: issue #60 Completed effort, with its sub-issues' >/dev/null
printf '%s\n' "$plan_output" | grep -F 'Stable branch: main at ' >/dev/null
printf '%s\n' "$plan_output" | grep -F "$root_worktree [feat/issue-60-root] via git" >/dev/null
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
  'feat/issue-66-active: worktree is locked' >/dev/null
# The name of the branch of open issue #75 also names #62, which is in scope.
printf '%s\n' "$plan_output" | grep -F \
  'feat/issue-75-port-62-fixes: issue #75 is open' >/dev/null
# The parent of #73 is issue 60 of another repository, not #60.
if printf '%s\n' "$plan_output" | grep -E 'feat/issue-(67|68|70|73|404)-' >/dev/null; then
  echo 'clean plan included a branch outside issue #60 and its sub-issues' >&2
  exit 1
fi

child_plan=$(cd "$primary" && run_clean example/agent-skills 61)
printf '%s\n' "$child_plan" | grep -F \
  'Clean plan: issue #61 Merged child, with its sub-issues' >/dev/null
printf '%s\n' "$child_plan" | grep -F "$child_worktree [feat/issue-61-child] via git" >/dev/null
if printf '%s\n' "$child_plan" | grep -F 'feat/issue-60-root' >/dev/null; then
  echo 'clean of a sub-issue included the branch of its parent' >&2
  exit 1
fi

[ -d "$root_worktree" ]
[ -d "$child_worktree" ]
"$real_git" -C "$primary" show-ref --verify --quiet refs/heads/feat/issue-60-root
"$real_git" --git-dir="$remote" show-ref --verify --quiet refs/heads/feat/issue-60-root

unmerged_output=$(cd "$primary" && run_clean example/agent-skills 63)
printf '%s\n' "$unmerged_output" | grep -F \
  'feat/issue-63-unmerged: branch tip is not verified in main' >/dev/null
printf '%s\n' "$unmerged_output" | grep -F 'Nothing is eligible for cleanup.' >/dev/null

open_effort_plan=$(cd "$primary" && run_clean example/agent-skills 67)
printf '%s\n' "$open_effort_plan" | grep -F \
  'feat/issue-67-open-effort: issue #67 is open' >/dev/null
printf '%s\n' "$open_effort_plan" | grep -F \
  "$open_task_worktree [feat/issue-68-merged-task] via git" >/dev/null
open_task_plan=$(cd "$primary" && run_clean example/agent-skills 68)
open_task_token=$(printf '%s\n' "$open_task_plan" | awk '/^Confirmation token:/ { print $3 }')
open_task_apply=$(cd "$primary" && run_clean --confirm "$open_task_token" example/agent-skills 68)
printf '%s\n' "$open_task_apply" | grep -F \
  'Cleanup applied: 1 worktree(s), 1 local branch(es), 1 remote branch(es).' >/dev/null
[ ! -d "$open_task_worktree" ]
[ -d "$open_effort_worktree" ]
"$real_git" -C "$primary" show-ref --verify --quiet refs/heads/feat/issue-67-open-effort

token=$(printf '%s\n' "$plan_output" | awk '/^Confirmation token:/ { print $3 }')
printf 'became dirty\n' >"$child_worktree/stale.txt"
if (cd "$primary" && run_clean --confirm "$token" example/agent-skills 60 >/dev/null 2>&1); then
  echo 'stale cleanup plan was accepted' >&2
  exit 1
fi
[ -d "$root_worktree" ]
[ -d "$child_worktree" ]
unlink "$child_worktree/stale.txt"

plan_output=$(cd "$primary" && run_clean example/agent-skills 60)
token=$(printf '%s\n' "$plan_output" | awk '/^Confirmation token:/ { print $3 }')
apply_output=$(cd "$primary" && run_clean --confirm "$token" example/agent-skills 60)
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
[ -d "$open_other_worktree" ]
for branch in feat/issue-73-foreign-parent feat/issue-75-port-62-fixes; do
  "$real_git" -C "$primary" show-ref --verify --quiet "refs/heads/$branch"
  "$real_git" --git-dir="$remote" show-ref --verify --quiet "refs/heads/$branch"
done

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

# The stable branch is the branch of the primary checkout, not the default
# branch. A task branch that reached only the stable branch is eligible, and
# the stable branch itself is never a candidate.
stable_task_worktree=$temporary_directory/issue-72
"$real_git" -C "$primary" branch feat/issue-71-stable main
create_worktree feat/issue-72-stable-task "$stable_task_worktree" feat/issue-71-stable stable-task.txt
stable_task_worktree=$("$real_git" -C "$stable_task_worktree" rev-parse --show-toplevel)
"$real_git" -C "$primary" switch -q feat/issue-71-stable
"$real_git" -C "$primary" merge -q --no-ff feat/issue-72-stable-task -m 'Merge stable task'
"$real_git" -C "$primary" push -q origin feat/issue-71-stable feat/issue-72-stable-task

stable_plan=$(cd "$primary" && run_clean example/agent-skills 71)
printf '%s\n' "$stable_plan" | grep -F 'Stable branch: feat/issue-71-stable at ' >/dev/null
printf '%s\n' "$stable_plan" | grep -F \
  "$stable_task_worktree [feat/issue-72-stable-task] via git" >/dev/null
if printf '%s\n' "$stable_plan" | grep -E '^- feat/issue-71-stable[: ]' >/dev/null; then
  echo 'clean plan listed the stable branch' >&2
  exit 1
fi

"$real_git" -C "$primary" switch -q --detach
if detached_output=$(cd "$primary" && run_clean example/agent-skills 71 2>&1); then
  echo 'cleanup ran from a detached primary checkout' >&2
  exit 1
fi
printf '%s\n' "$detached_output" | grep -F 'the primary checkout has no current branch' >/dev/null
"$real_git" -C "$primary" switch -q feat/issue-71-stable

[ ! -e "$fake_bin/supacode-calls" ]

printf 'gh-issue clean command tests passed\n'
