#!/bin/sh
set -eu
repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
finish_command=$repository_root/skills/engineering/gh-issue/scripts/finish.sh
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-finish-worktree.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
mkdir -p "$temporary_directory/bin"
cat >"$temporary_directory/bin/gh" <<'GH'
#!/bin/sh
set -eu
case "$1:$2" in
  api:graphql) cat "$GH_FINISH_FIXTURE" ;;
  pr:list) printf '%s\n' "${GH_PULL_REQUESTS:-[]}" ;;
  issue:close) printf '%s\n' "$*" >>"$GH_CALL_LOG" ;;
  *) exit 70 ;;
esac
GH
chmod +x "$temporary_directory/bin/gh"
export REAL_GIT="$(command -v git)"
cat >"$temporary_directory/bin/git" <<'GIT'
#!/bin/sh
if [ "$1" = remote ] && [ "$2" = get-url ]; then
  printf 'https://github.com/example/agent-skills.git\n'
else
  exec "$REAL_GIT" "$@"
fi
GIT
chmod +x "$temporary_directory/bin/git"
export PATH="$temporary_directory/bin:$PATH"
export GH_FINISH_FIXTURE="$repository_root/tests/gh-issue/fixtures/finish-40.json"
export GH_CALL_LOG="$temporary_directory/calls"
export AGENT_SKILLS_CONFIG="$temporary_directory/config.json"
printf '{"projectSync":{"enabled":false}}\n' >"$AGENT_SKILLS_CONFIG"
: >"$GH_CALL_LOG"
primary=$temporary_directory/primary
worktree=$temporary_directory/issue-40
remote=$temporary_directory/remote.git
git init -q --bare "$remote"
git init -q -b main "$primary"
git -C "$primary" config user.name Test
git -C "$primary" config user.email test@example.com
git -C "$primary" config "url.$remote.insteadOf" https://github.com/example/agent-skills.git
git -C "$primary" remote add origin https://github.com/example/agent-skills.git
for name in staged unstaged deleted renamed; do
  printf 'base\n' >"$primary/$name.txt"
done
git -C "$primary" add .
git -C "$primary" commit -qm Base
git -C "$primary" push -qu origin main
git -C "$primary" worktree add -qb feat/issue-40-changed "$worktree" main
run_finish() { (cd "$primary" && "$finish_command" "$@" example/agent-skills 40); }

printf 'staged\n' >>"$worktree/staged.txt"
git -C "$worktree" add staged.txt
printf 'unstaged\n' >>"$worktree/unstaged.txt"
rm "$worktree/deleted.txt"
git -C "$worktree" mv renamed.txt 'renamed file.txt'
printf 'new\n' >"$worktree/untracked file.txt"
status_before=$(git -C "$worktree" status --porcelain=v1 --untracked-files=all)
output=$(run_finish)
printf '%s\n' "$output" | grep -F 'Uncommitted paths (Git status):' >/dev/null
for path in staged.txt unstaged.txt deleted.txt 'renamed file.txt' 'untracked file.txt'; do
  printf '%s\n' "$output" | grep -F "$path" >/dev/null
done
[ ! -s "$GH_CALL_LOG" ]
[ "$(git -C "$worktree" status --porcelain=v1 --untracked-files=all)" = "$status_before" ]

# Committed and uncommitted changes both remain visible.
git -C "$worktree" commit -qm 'Commit staged changes'
output=$(run_finish --dry-run)
printf '%s\n' "$output" | grep -F 'Committed paths:' >/dev/null
printf '%s\n' "$output" | grep -F -- '- staged.txt' >/dev/null
printf '%s\n' "$output" | grep -F 'Uncommitted paths (Git status):' >/dev/null
[ ! -s "$GH_CALL_LOG" ]

# An untracked-only worktree must never close as no-change work.
git -C "$worktree" reset -q --hard main
output=$(run_finish)
printf '%s\n' "$output" | grep -F 'untracked file.txt' >/dev/null
[ ! -s "$GH_CALL_LOG" ]

# A merged PR with new local work must not silently close the issue.
export GH_PULL_REQUESTS='[{"state":"MERGED","url":"https://example.invalid/pr/40","baseRefName":"main"}]'
if run_finish >"$temporary_directory/merged-output" 2>&1; then
  echo 'finish accepted uncommitted work after a merged PR' >&2
  exit 1
fi
[ ! -s "$GH_CALL_LOG" ]
unset GH_PULL_REQUESTS
rm "$worktree/untracked file.txt"

# Unresolved merges remain blocked.
printf 'main version\n' >"$primary/staged.txt"
git -C "$primary" commit -qam 'Main change'
printf 'task version\n' >"$worktree/staged.txt"
git -C "$worktree" commit -qam 'Task change'
if git -C "$worktree" merge main >"$temporary_directory/merge-output" 2>&1; then exit 1; fi
if run_finish >"$temporary_directory/conflict-output" 2>&1; then
  echo 'finish accepted an unresolved merge' >&2
  exit 1
fi
grep -F 'unresolved conflicts' "$temporary_directory/conflict-output" >/dev/null
[ ! -s "$GH_CALL_LOG" ]
printf 'gh-issue finish worktree tests passed\n'
