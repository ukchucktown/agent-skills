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
squash_merged_worktree=$temporary_directory/squash-merged

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
create_worktree feat/squash-merged "$squash_merged_worktree" squash-merged.txt

for branch in feat/unselected feat/orphan-both feat/orphan-local feat/orphan-remote; do
  "$real_git" -C "$primary" merge -q --no-ff "$branch" -m "Merge $branch"
done
"$real_git" -C "$primary" merge -q --squash feat/squash-merged
"$real_git" -C "$primary" commit -q -m 'Squash merge feat/squash-merged'

"$real_git" -C "$primary" push -q -u origin main
"$real_git" -C "$primary" push -q origin \
  feat/leftover feat/active feat/protected feat/open-pr feat/unselected feat/locked \
  feat/squash-merged
"$real_git" -C "$primary" push -q origin feat/orphan-both feat/orphan-remote

"$real_git" -C "$primary" worktree remove "$orphan_both_worktree"
"$real_git" -C "$primary" worktree remove "$orphan_local_worktree"
"$real_git" -C "$primary" worktree remove "$orphan_remote_worktree"
"$real_git" -C "$primary" branch -D feat/orphan-remote >/dev/null

printf 'diverge\n' >>"$leftover_worktree/leftover.txt"
"$real_git" -C "$leftover_worktree" add leftover.txt
"$real_git" -C "$leftover_worktree" commit -q -m 'Diverge locally'
printf 'uncommitted\n' >"$leftover_worktree/uncommitted.txt"
"$real_git" -C "$primary" worktree lock "$locked_worktree" --reason other

remote=$(CDPATH= cd -- "$remote" && pwd -P)
primary=$("$real_git" -C "$primary" rev-parse --show-toplevel)
leftover_worktree=$("$real_git" -C "$leftover_worktree" rev-parse --show-toplevel)
active_worktree=$("$real_git" -C "$active_worktree" rev-parse --show-toplevel)
protected_worktree=$("$real_git" -C "$protected_worktree" rev-parse --show-toplevel)
open_pr_worktree=$("$real_git" -C "$open_pr_worktree" rev-parse --show-toplevel)
unselected_worktree=$("$real_git" -C "$unselected_worktree" rev-parse --show-toplevel)
locked_worktree=$("$real_git" -C "$locked_worktree" rev-parse --show-toplevel)
squash_merged_worktree=$("$real_git" -C "$squash_merged_worktree" rev-parse --show-toplevel)

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
if [ "${1:-}" = "worktree" ] && [ "${2:-}" = "remove" ]; then
  last=
  for argument in "$@"; do last=$argument; done
  if [ -n "${FAIL_WORKTREE_REMOVE_PATH:-}" ] && [ "$last" = "$FAIL_WORKTREE_REMOVE_PATH" ]; then
    printf 'injected worktree removal failure\n' >&2
    exit 71
  fi
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
        if [ "${LOCK_DURING_REVALIDATION_BRANCH:-}" = "$branch" ]; then
          "$REAL_GIT" -C "$CLEAN_PRIMARY" worktree lock \
            "$LOCK_DURING_REVALIDATION_PATH" --reason reserved
        fi
        oid=$("$REAL_GIT" --git-dir="$CLEAN_REMOTE" rev-parse "refs/heads/$branch")
        protected=false
        [ "$branch" != "feat/protected" ] || protected=true
        printf '%s\t%s\n' "$oid" "$protected"
        ;;
    esac
    ;;
  pr:list)
    branch=
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--head" ]; then
        branch=$2
        break
      fi
      shift
    done
    printf 'pr list --head %s\n' "$branch" >>"$GH_CALL_LOG"
    if [ "$branch" = "feat/squash-merged" ]; then
      oid=$("$REAL_GIT" --git-dir="$CLEAN_REMOTE" rev-parse "refs/heads/$branch")
      printf '[{"url":"https://github.com/example/agent-skills/pull/1","headRefOid":"%s"}]\n' "$oid"
    elif [ "$branch" = "feat/leftover" ]; then
      stale_oid=$("$REAL_GIT" --git-dir="$CLEAN_REMOTE" rev-parse refs/heads/main)
      printf '[{"url":"https://github.com/example/agent-skills/pull/2","headRefOid":"%s"}]\n' "$stale_oid"
    else
      printf '[]\n'
    fi
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

call_log=$temporary_directory/gh-calls.log
: >"$call_log"

run_clean() {
  PATH="$fake_bin:$PATH" \
  REAL_GIT="$real_git" \
  CLEAN_REPOSITORY_FIXTURE="$fixture" \
  CLEAN_REMOTE="$remote" \
  CLEAN_PRIMARY="$primary" \
  GH_CALL_LOG="$call_log" \
  LOCK_DURING_REVALIDATION_BRANCH="${lock_during_revalidation_branch:-}" \
  LOCK_DURING_REVALIDATION_PATH="${lock_during_revalidation_path:-}" \
  FAIL_WORKTREE_REMOVE_PATH="${fail_worktree_remove_path:-}" \
  "$clean_command" "$@"
}

assert_branch_once() {
  output=$1
  branch=$2
  occurrences=$(printf '%s\n' "$output" | awk -v branch="$branch" '
    index($0, branch) { count++ }
    END { print count + 0 }
  ')
  if [ "$occurrences" -ne 1 ]; then
    echo "expected $branch to appear once, found $occurrences occurrences" >&2
    exit 1
  fi
}

candidate_output=$(cd "$primary" && run_clean example/agent-skills)
printf '%s\n' "$candidate_output" | grep -F 'Repository cleanup candidates' >/dev/null
printf '%s\n' "$candidate_output" | grep -F 'Selectable branches (5)' >/dev/null
printf '%s\n' "$candidate_output" | grep -F 'Blocked branches (5)' >/dev/null
printf '%s\n' "$candidate_output" | grep -F \
  'Choose all selectable branches, comma-separated numbers or ranges, or exact branch names' >/dev/null
printf '%s\n' "$candidate_output" | grep -F \
  'worktree has uncommitted changes; local and remote tips differ; branch tip is not in main' >/dev/null
grep -F 'pr list --head feat/leftover' "$call_log" >/dev/null
printf '%s\n' "$candidate_output" | grep -F \
  'branch tip is not in main' >/dev/null
printf '%s\n' "$candidate_output" | grep -F \
  'Reason: remote branch is protected' >/dev/null
printf '%s\n' "$candidate_output" | grep -F \
  'Reason: open pull request' >/dev/null
printf '%s\n' "$candidate_output" | grep -F \
  'Reason: worktree is locked' >/dev/null
for branch in \
  feat/leftover feat/active feat/protected feat/open-pr feat/locked \
  feat/orphan-both feat/orphan-local feat/orphan-remote feat/unselected feat/squash-merged; do
  assert_branch_once "$candidate_output" "$branch"
done
printf '%s\n' "$candidate_output" | grep -F 'Worktree: none' >/dev/null
printf '%s\n' "$candidate_output" | grep -F 'References: local and remote at' >/dev/null
printf '%s\n' "$candidate_output" | grep -F 'Warnings: none' >/dev/null
grep -F 'pr list --head feat/squash-merged' "$call_log" >/dev/null
[ -d "$leftover_worktree" ]
[ -d "$active_worktree" ]

all_plan_output=$(cd "$primary" && run_clean --all example/agent-skills)
printf '%s\n' "$all_plan_output" | grep -F 'Risk policy: safe only' >/dev/null
printf '%s\n' "$all_plan_output" | grep -F 'Selected branches (5)' >/dev/null
printf '%s\n' "$all_plan_output" | grep -F 'Totals' >/dev/null
printf '%s\n' "$all_plan_output" | grep -F '  Worktrees to remove: 2' >/dev/null
printf '%s\n' "$all_plan_output" | grep -F '  Local branches to remove: 4' >/dev/null
printf '%s\n' "$all_plan_output" | grep -F '  Remote branches to remove: 4' >/dev/null
printf '%s\n' "$all_plan_output" | grep -F '  Unselected selectable branches: 0' >/dev/null
printf '%s\n' "$all_plan_output" | grep -F \
  'References: local and remote at' | grep -F '(remove both)' >/dev/null
for branch in feat/unselected feat/orphan-both feat/orphan-local feat/orphan-remote feat/squash-merged; do
  assert_branch_once "$all_plan_output" "$branch"
done
if printf '%s\n' "$all_plan_output" | grep -Fx 'Local branches to remove:' >/dev/null; then
  echo 'repository cleanup plan split local branches into a separate list' >&2
  exit 1
fi
if printf '%s\n' "$all_plan_output" | grep -Fx 'Remote branches to remove:' >/dev/null; then
  echo 'repository cleanup plan split remote branches into a separate list' >&2
  exit 1
fi

local_only_plan=$(cd "$primary" && run_clean \
  --local-only --select feat/unselected example/agent-skills)
printf '%s\n' "$local_only_plan" | grep -F \
  'References: local at ' | grep -F '(remove); remote at ' | grep -F '(preserve)' >/dev/null
printf '%s\n' "$local_only_plan" | grep -F '  Local branches to remove: 1' >/dev/null
printf '%s\n' "$local_only_plan" | grep -F '  Remote branches to remove: 0' >/dev/null
printf '%s\n' "$local_only_plan" | grep -F '  Preserved remote branches: 1' >/dev/null
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
  'Confirmed repository cleanup' >/dev/null
printf '%s\n' "$safe_apply_output" | grep -F \
  'Remove: 2 worktree(s), 4 local branch(es), and 4 remote branch(es) across 5 selected branch(es).' >/dev/null
printf '%s\n' "$safe_apply_output" | grep -F \
  'Repository cleanup applied: 2 worktree(s), 4 local branch(es), 4 remote branch(es).' >/dev/null
if printf '%s\n' "$safe_apply_output" | grep -F "$unselected_worktree" >/dev/null; then
  echo 'repository cleanup confirmation repeated worktree paths' >&2
  exit 1
fi
if printf '%s\n' "$safe_apply_output" | grep -F -- '- feat/unselected' >/dev/null; then
  echo 'repository cleanup confirmation repeated branch details' >&2
  exit 1
fi
[ ! -d "$unselected_worktree" ]
[ ! -d "$squash_merged_worktree" ]
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
if "$real_git" -C "$primary" show-ref --verify --quiet refs/heads/feat/squash-merged; then
  echo 'repository cleanup --all left the squash-merged local branch' >&2
  exit 1
fi
for branch in feat/orphan-both feat/orphan-remote; do
  if "$real_git" --git-dir="$remote" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "repository cleanup --all left remote branch $branch" >&2
    exit 1
  fi
done
if "$real_git" --git-dir="$remote" show-ref --verify --quiet refs/heads/feat/squash-merged; then
  echo 'repository cleanup --all left the squash-merged remote branch' >&2
  exit 1
fi

racy_lock_worktree=$temporary_directory/racy-lock
create_worktree feat/racy-lock "$racy_lock_worktree" racy-lock.txt
"$real_git" -C "$primary" push -q origin feat/racy-lock
racy_lock_worktree=$("$real_git" -C "$racy_lock_worktree" rev-parse --show-toplevel)

racy_plan=$(cd "$primary" && run_clean \
  --force --select feat/racy-lock example/agent-skills)
racy_token=$(printf '%s\n' "$racy_plan" | awk '/^Confirmation token:/ { print $3 }')
lock_during_revalidation_branch=feat/racy-lock
lock_during_revalidation_path=$racy_lock_worktree
racy_apply_output=$(cd "$primary" && run_clean \
  --force --select feat/racy-lock --confirm "$racy_token" example/agent-skills)
unset lock_during_revalidation_branch lock_during_revalidation_path
printf '%s\n' "$racy_apply_output" | grep -F \
  'Repository cleanup applied: 1 worktree(s), 1 local branch(es), 1 remote branch(es).' >/dev/null
[ ! -d "$racy_lock_worktree" ]
if "$real_git" -C "$primary" show-ref --verify --quiet refs/heads/feat/racy-lock; then
  echo 'forced repository cleanup left the newly locked local branch' >&2
  exit 1
fi
if "$real_git" --git-dir="$remote" show-ref --verify --quiet refs/heads/feat/racy-lock; then
  echo 'forced repository cleanup left the newly locked remote branch' >&2
  exit 1
fi

force_output=$(cd "$primary" && run_clean --force example/agent-skills)
printf '%s\n' "$force_output" | grep -F 'Selectable branches (2)' >/dev/null
printf '%s\n' "$force_output" | grep -F 'Blocked branches (3)' >/dev/null
printf '%s\n' "$force_output" | grep -F \
  'Warnings: worktree has uncommitted changes; local and remote tips differ; branch tip is not in main' >/dev/null
printf '%s\n' "$force_output" | grep -F \
  'Warnings: branch tip is not in main' >/dev/null
assert_branch_once "$force_output" feat/leftover
assert_branch_once "$force_output" feat/active

force_plan=$(cd "$primary" && run_clean --force --all example/agent-skills)
printf '%s\n' "$force_plan" | grep -F 'Risk policy: force' >/dev/null
printf '%s\n' "$force_plan" | grep -F 'Selected branches (2)' >/dev/null
assert_branch_once "$force_plan" feat/leftover
assert_branch_once "$force_plan" feat/active
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
  'Confirmed repository cleanup' >/dev/null
printf '%s\n' "$force_apply_output" | grep -F \
  'Risk policy: force' >/dev/null
printf '%s\n' "$force_apply_output" | grep -F \
  'Repository cleanup applied: 2 worktree(s), 2 local branch(es), 2 remote branch(es).' >/dev/null
if printf '%s\n' "$force_apply_output" | grep -F "$leftover_worktree" >/dev/null; then
  echo 'forced repository cleanup confirmation repeated worktree paths' >&2
  exit 1
fi
if printf '%s\n' "$force_apply_output" | grep -F -- '- feat/leftover' >/dev/null; then
  echo 'forced repository cleanup confirmation repeated branch details' >&2
  exit 1
fi
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

partial_a_worktree=$temporary_directory/partial-a
partial_b_worktree=$temporary_directory/partial-b
create_worktree feat/partial-a "$partial_a_worktree" partial-a.txt
create_worktree feat/partial-b "$partial_b_worktree" partial-b.txt
partial_a_worktree=$("$real_git" -C "$partial_a_worktree" rev-parse --show-toplevel)
partial_b_worktree=$("$real_git" -C "$partial_b_worktree" rev-parse --show-toplevel)

partial_plan=$(cd "$primary" && run_clean --force \
  --select feat/partial-a --select feat/partial-b example/agent-skills)
partial_token=$(printf '%s\n' "$partial_plan" | awk '/^Confirmation token:/ { print $3 }')
fail_worktree_remove_path=$partial_b_worktree
if partial_output=$(cd "$primary" && run_clean --force \
  --select feat/partial-a --select feat/partial-b --confirm "$partial_token" \
  example/agent-skills 2>&1); then
  echo 'repository cleanup ignored an injected worktree removal failure' >&2
  exit 1
fi
unset fail_worktree_remove_path
printf '%s\n' "$partial_output" | grep -F \
  'Repository cleanup may be partially applied.' >/dev/null
printf '%s\n' "$partial_output" | grep -F \
  'Completed before failure: 1 worktree removal(s), 0 local branch deletion(s), 0 remote branch deletion(s).' >/dev/null
[ ! -d "$partial_a_worktree" ]
[ -d "$partial_b_worktree" ]

for worktree in "$protected_worktree" "$open_pr_worktree" "$locked_worktree"; do
  [ -d "$worktree" ]
done
for branch in feat/protected feat/open-pr feat/locked; do
  "$real_git" -C "$primary" show-ref --verify --quiet "refs/heads/$branch"
  "$real_git" --git-dir="$remote" show-ref --verify --quiet "refs/heads/$branch"
done
# The stable branch is the branch of the primary checkout. The default branch
# stays blocked when another worktree uses it.
default_worktree=$temporary_directory/default
develop_task_worktree=$temporary_directory/develop-task
"$real_git" -C "$primary" switch -q -c develop
"$real_git" -C "$primary" worktree add -q "$default_worktree" main
"$real_git" -C "$primary" worktree add -q -b feat/develop-task "$develop_task_worktree" develop
printf 'develop task\n' >"$develop_task_worktree/develop-task.txt"
"$real_git" -C "$develop_task_worktree" add develop-task.txt
"$real_git" -C "$develop_task_worktree" commit -q -m 'Add develop task'
"$real_git" -C "$primary" merge -q --no-ff feat/develop-task -m 'Merge develop task'
"$real_git" -C "$primary" push -q origin develop feat/develop-task
default_worktree=$("$real_git" -C "$default_worktree" rev-parse --show-toplevel)

stable_output=$(cd "$primary" && run_clean example/agent-skills)
printf '%s\n' "$stable_output" | grep -F 'Stable branch: develop at ' >/dev/null
printf '%s\n' "$stable_output" | grep -E '^[0-9]+\. feat/develop-task$' >/dev/null
printf '%s\n' "$stable_output" | grep -F -A 2 -- '- main' |
  grep -F 'Reason: default branch cannot be selected' >/dev/null
if default_output=$(cd "$primary" && run_clean --select main example/agent-skills 2>&1); then
  echo 'repository cleanup accepted the default branch' >&2
  exit 1
fi
printf '%s\n' "$default_output" | grep -F \
  'branch main cannot be selected: default branch cannot be selected' >/dev/null
[ -d "$default_worktree" ]

[ ! -e "$fake_bin/supacode-calls" ]

printf 'gh-issue repository clean command tests passed\n'
