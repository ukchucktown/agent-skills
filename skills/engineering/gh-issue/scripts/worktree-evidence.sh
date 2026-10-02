#!/bin/sh
set -eu

# Collect read-only evidence about a local issue worktree. The output is one
# JSON object. Supacode is "absent" without the CLI, "unavailable" when the CLI
# fails, and "untracked" when Supacode does not manage the worktree. The
# summary field is the shared text form for status and start.

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

supacode_state=absent
supacode_tabs=null
if command -v supacode >/dev/null 2>&1; then
  worktree_id=$(jq -nr --arg value "$worktree_path/" '$value | @uri')
  if worktree_ids=$(supacode worktree list --timeout 5 2>/dev/null); then
    if printf '%s\n' "$worktree_ids" | grep -Fx "$worktree_id" >/dev/null; then
      if tab_ids=$(supacode tab list -w "$worktree_id" --timeout 5 2>/dev/null); then
        supacode_state=available
        own_tab=
        if [ "${SUPACODE_WORKTREE_ID:-}" = "$worktree_id" ]; then
          own_tab=${SUPACODE_TAB_ID:-}
        fi
        supacode_tabs=$(printf '%s\n' "$tab_ids" | awk -v own="$own_tab" '
          NF && toupper($0) != toupper(own) { count++ }
          END { print count + 0 }
        ')
      else
        supacode_state=unavailable
      fi
    else
      supacode_state=untracked
    fi
  else
    supacode_state=unavailable
  fi
fi

uncommitted=$(git --no-optional-locks -C "$worktree_path" status --porcelain | awk 'NF { count++ } END { print count + 0 }')
branch_commits=$(git -C "$worktree_path" rev-list --count HEAD --not \
  --exclude="$branch" --branches --exclude="*/$branch" --remotes)
last_commit_epoch=$(git -C "$worktree_path" log -1 --format=%ct HEAD)

case "$supacode_state" in
  available) summary="Supacode tabs $supacode_tabs, " ;;
  unavailable) summary="Supacode unavailable, " ;;
  untracked) summary="not in Supacode, " ;;
  *) summary= ;;
esac
summary="${summary}branch commits $branch_commits"
if [ "$branch_commits" -gt 0 ]; then
  summary="$summary (last $(age_text "$last_commit_epoch"))"
fi
summary="$summary, uncommitted changes $uncommitted"

jq -cn \
  --arg path "$worktree_path" \
  --arg branch "$branch" \
  --arg supacode "$supacode_state" \
  --argjson supacodeTabs "$supacode_tabs" \
  --argjson branchCommits "$branch_commits" \
  --argjson lastCommitEpoch "$last_commit_epoch" \
  --argjson uncommitted "$uncommitted" \
  --arg summary "$summary" \
  '{path: $path, branch: $branch, supacode: $supacode, supacodeTabs: $supacodeTabs,
    branchCommits: $branchCommits, lastCommitEpoch: $lastCommitEpoch,
    uncommitted: $uncommitted, summary: $summary}'
