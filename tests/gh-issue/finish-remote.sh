#!/bin/sh
set -eu
repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
finish_command=$repository_root/skills/engineering/gh-issue/scripts/finish.sh
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-finish-remote.XXXXXX")
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
if [ "${FAIL_FETCH:-false}" = true ]; then
  for argument in "$@"; do
    if [ "$argument" = fetch ]; then exit 1; fi
  done
fi
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
printf '{}\n' >"$AGENT_SKILLS_CONFIG"
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
printf 'base\n' >"$primary/base.txt"
git -C "$primary" add .
git -C "$primary" commit -qm Base
git -C "$primary" push -qu origin main
git -C "$primary" worktree add -qb feat/issue-40-changed "$worktree" main
run_finish() { (cd "$primary" && "$finish_command" "$@" example/agent-skills 40); }

# Remote main advances while local main and origin/main remain stale.
git -C "$primary" checkout -qb advance
printf 'upstream\n' >"$primary/upstream.txt"
git -C "$primary" add upstream.txt
git -C "$primary" commit -qm 'Advance remote main'
remote_tip=$(git -C "$primary" rev-parse HEAD)
git --git-dir="$remote" fetch -q "$primary" advance:main
git -C "$primary" checkout -q main
git -C "$worktree" merge -q --ff-only advance
printf 'issue change\n' >"$worktree/change.txt"
git -C "$worktree" add change.txt
git -C "$worktree" commit -qm 'Issue change'
local_tip=$(git -C "$primary" rev-parse main)
output=$(run_finish --dry-run)
printf '%s\n' "$output" | grep -Fx -- '- change.txt' >/dev/null
if printf '%s\n' "$output" | grep -F -- '- upstream.txt'; then
  echo 'finish included an unrelated upstream path' >&2
  exit 1
fi
[ "$(git -C "$primary" rev-parse origin/main)" = "$remote_tip" ]
[ "$(git -C "$primary" rev-parse main)" = "$local_tip" ]
[ ! -s "$GH_CALL_LOG" ]

# A local branch is valid only when origin has no branch with that name.
git -C "$primary" branch local-only advance
output=$(run_finish --base local-only --dry-run)
printf '%s\n' "$output" | grep -Fx 'Base: local-only' >/dev/null
printf '%s\n' "$output" | grep -Fx -- '- change.txt' >/dev/null

# A remote-only base is fetched without a local branch.
git --git-dir="$remote" update-ref refs/heads/remote-only "$remote_tip"
output=$(run_finish --base remote-only --dry-run)
printf '%s\n' "$output" | grep -Fx -- '- change.txt' >/dev/null

# A successful lookup cannot hide a subsequent fetch failure.
export FAIL_FETCH=true
if run_finish --dry-run >"$temporary_directory/fetch-failure" 2>&1; then
  echo 'finish accepted a failed fetch' >&2
  exit 1
fi
grep -F 'cannot fetch remote base branch main' "$temporary_directory/fetch-failure" >/dev/null
unset FAIL_FETCH

# A deleted remote base cannot survive through a stale tracking reference.
git -C "$primary" update-ref refs/remotes/origin/deleted "$remote_tip"
if run_finish --base deleted --dry-run >"$temporary_directory/missing" 2>&1; then
  echo 'finish reused a deleted remote base' >&2
  exit 1
fi

# Remote failures cannot silently select a stale local base.
mv "$remote" "$remote.offline"
if run_finish --dry-run >"$temporary_directory/offline" 2>&1; then
  echo 'finish accepted an unavailable remote' >&2
  exit 1
fi
grep -F 'cannot inspect remote base branch main' "$temporary_directory/offline" >/dev/null
[ ! -s "$GH_CALL_LOG" ]
printf 'gh-issue finish remote tests passed\n'
