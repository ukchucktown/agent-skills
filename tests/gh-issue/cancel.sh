#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cancel_command=$repository_root/skills/engineering/gh-issue/scripts/cancel.sh
fixture_directory=$repository_root/tests/gh-issue/fixtures
fake_graphql=$repository_root/tests/gh-issue/fake-graphql.sh
real_git=$(command -v git)

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-cancel-tests.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

remote=$temporary_directory/remote.git
primary=$temporary_directory/repository
root_worktree=$temporary_directory/issue-80
dirty_worktree=$temporary_directory/issue-81
active_worktree=$temporary_directory/issue-82
protected_worktree=$temporary_directory/issue-83

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
  filename=$3
  "$real_git" -C "$primary" worktree add -q -b "$branch" "$path" main
  printf '%s\n' "$branch" >"$path/$filename"
  "$real_git" -C "$path" add "$filename"
  "$real_git" -C "$path" commit -q -m "Add $filename"
}

create_worktree feat/issue-80-root "$root_worktree" root.txt
create_worktree feat/issue-81-dirty-divergent "$dirty_worktree" dirty.txt
create_worktree feat/issue-82-active "$active_worktree" active.txt
create_worktree feat/issue-83-protected "$protected_worktree" protected.txt
"$real_git" -C "$primary" branch feat/issue-999-unrelated main

"$real_git" -C "$primary" push -q -u origin main
"$real_git" -C "$primary" push -q origin \
  feat/issue-80-root \
  feat/issue-81-dirty-divergent \
  feat/issue-82-active \
  feat/issue-83-protected \
  feat/issue-999-unrelated

printf 'local only\n' >>"$dirty_worktree/dirty.txt"
"$real_git" -C "$dirty_worktree" add dirty.txt
"$real_git" -C "$dirty_worktree" commit -q -m 'Diverge locally'
printf 'uncommitted\n' >"$dirty_worktree/uncommitted.txt"

remote=$(CDPATH= cd -- "$remote" && pwd -P)
primary=$("$real_git" -C "$primary" rev-parse --show-toplevel)
root_worktree=$("$real_git" -C "$root_worktree" rev-parse --show-toplevel)
dirty_worktree=$("$real_git" -C "$dirty_worktree" rev-parse --show-toplevel)
active_worktree=$("$real_git" -C "$active_worktree" rev-parse --show-toplevel)
protected_worktree=$("$real_git" -C "$protected_worktree" rev-parse --show-toplevel)

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
case " $* " in
  *' worktree remove '*|*' branch -D '*|*' push origin --delete '*)
    printf 'git %s\n' "$*" >>"$GH_CALL_LOG"
    ;;
esac
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
        "$REAL_GIT" --git-dir="$CANCEL_REMOTE" for-each-ref \
          --format='%(refname:strip=2)%09%(objectname)' refs/heads |
          while IFS="$(printf '\t')" read -r branch oid; do
            protected=false
            [ "$branch" != "feat/issue-83-protected" ] || protected=true
            printf '%s\t%s\t%s\n' "$branch" "$oid" "$protected"
          done
        ;;
      *)
        encoded=${endpoint##*/}
        branch=$(printf '%s' "$encoded" | sed 's/%2F/\//g; s/%2f/\//g')
        oid=$("$REAL_GIT" --git-dir="$CANCEL_REMOTE" rev-parse "refs/heads/$branch")
        protected=false
        [ "$branch" != "feat/issue-83-protected" ] || protected=true
        printf '%s\t%s\n' "$oid" "$protected"
        ;;
    esac
    ;;
  pr:close)
    printf '%s\n' "$*" >>"$GH_CALL_LOG"
    ;;
  issue:close)
    printf '%s\n' "$*" >>"$GH_CALL_LOG"
    [ "${GH_FAIL_ISSUE:-}" != "${3:-}" ] || exit 1
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
graphql_log=$temporary_directory/graphql-calls.log
: >"$graphql_log"

run_cancel() {
  PATH="$fake_bin:$PATH" \
  REAL_GIT="$real_git" \
  GH_FAKE_GRAPHQL="$fake_graphql" \
  GH_ISSUE_GRAPH="${CANCEL_GRAPH:-$fixture_directory/cancel-graph.json}" \
  GH_GRAPHQL_LOG="$graphql_log" \
  GH_PAGE_SIZE=2 \
  GH_CALL_LOG="$call_log" \
  GH_FAIL_ISSUE="${GH_FAIL_ISSUE:-}" \
  GH_TRUNCATED="${GH_TRUNCATED:-false}" \
  CANCEL_REMOTE="$remote" \
  CANCEL_PRIMARY="$primary" \
  "$cancel_command" "$@"
}

plan_output=$(cd "$primary" && run_cancel example/agent-skills 81)
printf '%s\n' "$plan_output" | grep -F \
  'Cancel plan: issue #81 resolves to #80 Abandoned effort' >/dev/null
printf '%s\n' "$plan_output" | grep -F 'Issues to close as Not planned: 5' >/dev/null
printf '%s\n' "$plan_output" | grep -F '#85 Grandchild without a branch' >/dev/null
# Page size 2 splits the four sub-issues of #80 into two pages.
grep -F "$(printf 'clean-subissues\t80\t\n')" "$graphql_log" >/dev/null
grep -F "$(printf 'clean-subissues\t80\t2')" "$graphql_log" >/dev/null
grep -F "$(printf 'clean-subissues\t81\t\n')" "$graphql_log" >/dev/null
printf '%s\n' "$plan_output" | grep -F '#84 Already closed child' >/dev/null && {
  echo 'cancel plan included an already closed issue' >&2
  exit 1
}
printf '%s\n' "$plan_output" | grep -F \
  '#182 https://github.com/example/agent-skills/pull/182 [feat/issue-82-active]' >/dev/null
printf '%s\n' "$plan_output" | grep -F \
  'feat/issue-81-dirty-divergent: local and remote tips differ; worktree has uncommitted changes' >/dev/null
printf '%s\n' "$plan_output" | grep -F \
  'feat/issue-82-active: open pull request will close: https://github.com/example/agent-skills/pull/182' >/dev/null
printf '%s\n' "$plan_output" | grep -F \
  'feat/issue-83-protected: remote branch is protected' >/dev/null
printf '%s\n' "$plan_output" | grep -F 'feat/issue-999-unrelated' >/dev/null && {
  echo 'cancel plan included an unrelated branch' >&2
  exit 1
}
[ ! -s "$call_log" ]
[ -d "$root_worktree" ]
[ -d "$dirty_worktree" ]
[ -d "$active_worktree" ]

"$real_git" -C "$primary" worktree lock "$root_worktree" --reason reserved
locked_plan=$(cd "$primary" && run_cancel example/agent-skills 81)
printf '%s\n' "$locked_plan" | grep -F \
  'feat/issue-80-root: worktree is locked' >/dev/null
[ -d "$root_worktree" ]
[ ! -s "$call_log" ]
"$real_git" -C "$primary" worktree unlock "$root_worktree"

if truncated_output=$(cd "$primary" && GH_TRUNCATED=true run_cancel example/agent-skills 81 2>&1); then
  echo 'cancel accepted truncated GitHub data' >&2
  exit 1
fi
printf '%s\n' "$truncated_output" | grep -F \
  'GitHub returned 4 of 5 sub-issues of #80' >/dev/null
[ ! -s "$call_log" ]

# Cancel closes issues by number in this repository, so a hierarchy that
# leaves the repository stops the command.
foreign_child_graph=$temporary_directory/foreign-child-graph.json
jq '.issues += [{repository: "other/project", number: 12,
  title: "Sub-issue in another repository", state: "OPEN", parent: 80, linked: []}]' \
  "$fixture_directory/cancel-graph.json" >"$foreign_child_graph"
if foreign_output=$(cd "$primary" && CANCEL_GRAPH=$foreign_child_graph run_cancel example/agent-skills 81 2>&1); then
  echo 'cancel accepted a sub-issue in another repository' >&2
  exit 1
fi
printf '%s\n' "$foreign_output" | grep -F \
  'cancel works in one repository, but #80 has the sub-issue other/project#12' >/dev/null
[ ! -s "$call_log" ]

foreign_parent_graph=$temporary_directory/foreign-parent-graph.json
jq '(.issues[] | select(.number == 80) | .parent) = {repository: "other/project", number: 5} |
  .issues += [{repository: "other/project", number: 5,
    title: "Effort in another repository", state: "OPEN", parent: null, linked: []}]' \
  "$fixture_directory/cancel-graph.json" >"$foreign_parent_graph"
if foreign_output=$(cd "$primary" && CANCEL_GRAPH=$foreign_parent_graph run_cancel example/agent-skills 81 2>&1); then
  echo 'cancel accepted a parent in another repository' >&2
  exit 1
fi
printf '%s\n' "$foreign_output" | grep -F \
  'cancel works in one repository, but the parents of #81 include other/project#5' >/dev/null
[ ! -s "$call_log" ]

token=$(printf '%s\n' "$plan_output" | awk '/^Confirmation token:/ { print $3 }')
printf 'stale plan\n' >>"$dirty_worktree/dirty.txt"
"$real_git" -C "$dirty_worktree" add dirty.txt
"$real_git" -C "$dirty_worktree" commit -q -m 'Change cancellation plan'
if (cd "$primary" && run_cancel --confirm "$token" example/agent-skills 81 >/dev/null 2>&1); then
  echo 'stale cancellation plan was accepted' >&2
  exit 1
fi
[ ! -s "$call_log" ]
[ -d "$dirty_worktree" ]

plan_output=$(cd "$primary" && run_cancel example/agent-skills 81)
token=$(printf '%s\n' "$plan_output" | awk '/^Confirmation token:/ { print $3 }')
if (cd "$primary" && GH_FAIL_ISSUE=80 run_cancel --confirm "$token" example/agent-skills 81 >/dev/null 2>&1); then
  echo 'cancel continued after failing to close an issue' >&2
  exit 1
fi
grep -F 'pr close 182 --repo example/agent-skills' "$call_log" >/dev/null
grep -F 'issue close 80 --repo example/agent-skills --reason not planned' "$call_log" >/dev/null
if grep -E '^(git (worktree remove|branch -D|push origin --delete))' "$call_log" >/dev/null; then
  echo 'cancel removed an artifact after failing to close an issue' >&2
  exit 1
fi
[ -d "$root_worktree" ]
[ -d "$dirty_worktree" ]
[ -d "$active_worktree" ]
: >"$call_log"

plan_output=$(cd "$primary" && run_cancel example/agent-skills 81)
token=$(printf '%s\n' "$plan_output" | awk '/^Confirmation token:/ { print $3 }')
apply_output=$(cd "$primary" && run_cancel --confirm "$token" example/agent-skills 81)
printf '%s\n' "$apply_output" | grep -F \
  'Confirmed cancellation plan summary' >/dev/null
printf '%s\n' "$apply_output" | grep -F \
  'Worktrees to remove: 3' >/dev/null
printf '%s\n' "$apply_output" | grep -F \
  'Cancellation applied: 5 issue(s), 1 pull request(s), 3 worktree(s), 3 local branch(es), 3 remote branch(es).' >/dev/null
if printf '%s\n' "$apply_output" | grep -F "$root_worktree" >/dev/null; then
  echo 'cancel confirmation repeated worktree paths' >&2
  exit 1
fi
if printf '%s\n' "$apply_output" | grep -F 'feat/issue-80-root at ' >/dev/null; then
  echo 'cancel confirmation repeated branch details' >&2
  exit 1
fi

grep -F 'pr close 182 --repo example/agent-skills' "$call_log" >/dev/null
for issue in 80 81 82 83 85; do
  grep -F "issue close $issue --repo example/agent-skills --reason not planned" "$call_log" >/dev/null
done
if grep -F 'issue close 84 ' "$call_log" >/dev/null; then
  echo 'cancel closed an already closed issue' >&2
  exit 1
fi

issue_close_line() {
  grep -n -m 1 "^issue close $1 " "$call_log" | cut -d: -f1
}
[ "$(issue_close_line 85)" -lt "$(issue_close_line 81)" ] &&
  [ "$(issue_close_line 81)" -lt "$(issue_close_line 80)" ] || {
  echo 'cancel did not close sub-issues before their parents' >&2
  exit 1
}

pr_close_line=$(grep -n -m 1 '^pr close ' "$call_log" | cut -d: -f1)
first_issue_close_line=$(grep -n -m 1 '^issue close ' "$call_log" | cut -d: -f1)
last_issue_close_line=$(grep -n '^issue close ' "$call_log" | tail -n 1 | cut -d: -f1)
first_cleanup_line=$(grep -n -m 1 -E '^(git (worktree remove|branch -D|push origin --delete))' "$call_log" | cut -d: -f1)
[ "$pr_close_line" -lt "$first_issue_close_line" ] || {
  echo 'cancel did not close pull requests before issues' >&2
  exit 1
}
[ "$last_issue_close_line" -lt "$first_cleanup_line" ] || {
  echo 'cancel removed worktrees or branches before closing every issue' >&2
  exit 1
}

[ ! -d "$root_worktree" ]
[ ! -d "$dirty_worktree" ]
[ ! -d "$active_worktree" ]
[ -d "$protected_worktree" ]
for branch in feat/issue-80-root feat/issue-81-dirty-divergent feat/issue-82-active; do
  if "$real_git" -C "$primary" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "cancel left local branch $branch" >&2
    exit 1
  fi
  if "$real_git" --git-dir="$remote" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "cancel left remote branch $branch" >&2
    exit 1
  fi
done
"$real_git" -C "$primary" show-ref --verify --quiet refs/heads/feat/issue-83-protected
"$real_git" --git-dir="$remote" show-ref --verify --quiet refs/heads/feat/issue-83-protected
"$real_git" -C "$primary" show-ref --verify --quiet refs/heads/feat/issue-999-unrelated
"$real_git" --git-dir="$remote" show-ref --verify --quiet refs/heads/feat/issue-999-unrelated

[ ! -e "$fake_bin/supacode-calls" ]

printf 'gh-issue cancel command tests passed\n'
