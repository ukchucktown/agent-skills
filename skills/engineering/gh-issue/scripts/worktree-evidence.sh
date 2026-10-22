#!/bin/sh
set -eu

# Collect read-only Git evidence about a local issue worktree. The output is
# one JSON object. The summary field is shared by status and start.

usage() {
  echo "usage: worktree-evidence.sh WORKTREE_PATH BRANCH" >&2
  exit 64
}

plural() {
  if [ "$1" -eq 1 ]; then printf '%s %s' "$1" "$2"; else printf '%s %ss' "$1" "$2"; fi
}

age_text() {
  seconds=$(($(date +%s) - $1))
  if [ "$seconds" -lt 60 ]; then
    printf 'less than a minute ago'
  elif [ "$seconds" -lt 3600 ]; then
    printf '%s ago' "$(plural $((seconds / 60)) minute)"
  elif [ "$seconds" -lt 86400 ]; then
    printf '%s ago' "$(plural $((seconds / 3600)) hour)"
  else
    printf '%s ago' "$(plural $((seconds / 86400)) day)"
  fi
}

[ "$#" -eq 2 ] || usage
worktree_path=${1%/}
branch=$2
[ -d "$worktree_path" ] || {
  echo "worktree-evidence.sh: $worktree_path is not a directory" >&2
  exit 66
}

uncommitted=$(git --no-optional-locks -C "$worktree_path" status --porcelain | awk 'NF { count++ } END { print count + 0 }')
branch_commits=$(git -C "$worktree_path" rev-list --count HEAD --not \
  --exclude="$branch" --branches --exclude="*/$branch" --remotes)
last_commit_epoch=$(git -C "$worktree_path" log -1 --format=%ct HEAD)

summary="branch commits $branch_commits"
if [ "$branch_commits" -gt 0 ]; then
  summary="$summary (last $(age_text "$last_commit_epoch"))"
fi
summary="$summary, uncommitted changes $uncommitted"

jq -cn \
  --arg path "$worktree_path" \
  --arg branch "$branch" \
  --argjson branchCommits "$branch_commits" \
  --argjson lastCommitEpoch "$last_commit_epoch" \
  --argjson uncommitted "$uncommitted" \
  --arg summary "$summary" \
  '{path: $path, branch: $branch,
    branchCommits: $branchCommits, lastCommitEpoch: $lastCommitEpoch,
    uncommitted: $uncommitted, summary: $summary}'
