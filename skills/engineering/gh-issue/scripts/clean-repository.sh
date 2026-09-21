#!/bin/sh
set -eu

usage() {
  echo "usage: clean.sh [--local-only] [--select BRANCH]... [--confirm TOKEN] OWNER/REPOSITORY|." >&2
  exit 64
}

local_only=false
confirmation=
selected_branches=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --local-only)
      local_only=true
      shift
      ;;
    --select)
      [ "$#" -ge 2 ] || usage
      selected_branches="${selected_branches}${selected_branches:+
}$2"
      shift 2
      ;;
    --confirm)
      [ "$#" -ge 2 ] || usage
      confirmation=$2
      shift 2
      ;;
    --) shift; break ;;
    -*) usage ;;
    *) break ;;
  esac
done

[ "$#" -eq 1 ] || usage
repository=$1

for command in git gh jq; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "clean.sh: $command is required" >&2
    exit 69
  }
done

hash_plan() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{ print $1 }'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{ print $1 }'
  else
    echo "clean.sh: shasum or sha256sum is required" >&2
    return 69
  fi
}

if [ "$repository" = "." ]; then
  current_remote=$(git remote get-url origin 2>/dev/null) || {
    echo "clean.sh: cannot resolve the current repository's origin" >&2
    exit 2
  }
  case "$current_remote" in
    git@github.com:*) repository=${current_remote#git@github.com:} ;;
    https://github.com/*) repository=${current_remote#https://github.com/} ;;
    ssh://git@github.com/*) repository=${current_remote#ssh://git@github.com/} ;;
    *)
      echo "clean.sh: origin is not a github.com repository: $current_remote" >&2
      exit 2
      ;;
  esac
  repository=${repository%.git}
fi

case "$repository" in
  */*) ;;
  *) usage ;;
esac
owner=${repository%%/*}
name=${repository#*/}
[ -n "$owner" ] && [ -n "$name" ] || usage
case "$name" in
  */*) usage ;;
esac

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
query=$script_directory/../references/clean-repository.graphql
if ! repository_json=$(gh api graphql \
  -F "owner=$owner" \
  -F "name=$name" \
  -F "query=@$query" 2>&1); then
  printf 'clean.sh: cannot inspect repository cleanup candidates\n%s\n' "$repository_json" >&2
  exit 2
fi

if ! canonical_repository=$(printf '%s' "$repository_json" | jq -er '
  if .data.repository == null then error("repository not found")
  elif .data.repository.openPullRequests.totalCount >
       (.data.repository.openPullRequests.nodes | length) then
    error("open pull request list was truncated")
  else .data.repository.nameWithOwner end
'); then
  echo "clean.sh: GitHub returned incomplete repository cleanup data" >&2
  exit 2
fi
stable_branch=$(printf '%s' "$repository_json" | jq -er '.data.repository.defaultBranchRef.name')

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "clean.sh: run this command from the primary checkout of $canonical_repository" >&2
  exit 2
}
current_remote=$(git remote get-url origin 2>/dev/null || true)
case "$current_remote" in
  git@github.com:*) current_repository=${current_remote#git@github.com:} ;;
  https://github.com/*) current_repository=${current_remote#https://github.com/} ;;
  ssh://git@github.com/*) current_repository=${current_remote#ssh://git@github.com/} ;;
  *) current_repository= ;;
esac
current_repository=${current_repository%.git}
[ "$current_repository" = "$canonical_repository" ] || {
  echo "clean.sh: the current checkout is $current_repository, not $canonical_repository" >&2
  exit 2
}

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-repository-clean.XXXXXX")
trap 'find "$temporary_directory" -type f -delete 2>/dev/null || true; rmdir "$temporary_directory" 2>/dev/null || true' EXIT HUP INT TERM

worktrees_file=$temporary_directory/worktrees
git worktree list --porcelain >"$worktrees_file"
primary_checkout=$(awk '/^worktree / { print substr($0, 10); exit }' "$worktrees_file")
current_checkout=$(git rev-parse --show-toplevel)
current_branch=$(git branch --show-current)
[ "$current_checkout" = "$primary_checkout" ] && [ "$current_branch" = "$stable_branch" ] || {
  echo "clean.sh: run this command from the primary checkout on $stable_branch" >&2
  exit 2
}
[ -z "$(git status --porcelain=v1)" ] || {
  echo "clean.sh: the primary checkout has uncommitted changes" >&2
  exit 2
}

remote_branches=$temporary_directory/remote-branches
if ! gh api --paginate "repos/$canonical_repository/branches?per_page=100" \
  --jq '.[] | [.name, .commit.sha, .protected] | @tsv' >"$remote_branches"; then
  echo "clean.sh: cannot read remote branch protection and tip data" >&2
  exit 2
fi
stable_oid=$(awk -F '\t' -v branch="$stable_branch" '$1 == branch { print $2; exit }' "$remote_branches")
[ -n "$stable_oid" ] || {
  echo "clean.sh: remote stable branch $stable_branch was not found" >&2
  exit 2
}
current_oid=$(git rev-parse HEAD)
[ "$current_oid" = "$stable_oid" ] || {
  echo "clean.sh: the primary checkout is not synchronized with origin/$stable_branch" >&2
  exit 2
}

local_branches=$temporary_directory/local-branches
git for-each-ref --format='%(refname:strip=2)%09%(objectname)' refs/heads >"$local_branches"
open_prs=$temporary_directory/open-prs
printf '%s' "$repository_json" | jq -r '
  .data.repository.openPullRequests.nodes[] |
  [.headRefName, (.number | tostring), .url] | @tsv
' >"$open_prs"

worktree_rows=$temporary_directory/worktree-rows
awk '
  function emit() {
    if (path != "") {
      if (branch == "") branch = "(detached)"
      print path "\t" branch "\t" locked
    }
  }
  /^worktree / { emit(); path = substr($0, 10); branch = ""; locked = "false"; next }
  /^branch refs\/heads\// { branch = substr($0, 19); next }
  /^locked/ { locked = "true"; next }
  /^$/ { emit(); path = ""; branch = ""; locked = "false" }
  END { emit() }
' "$worktrees_file" >"$worktree_rows"

supacode_worktrees=$temporary_directory/supacode-worktrees
supacode_focused=$temporary_directory/supacode-focused
: >"$supacode_worktrees"
: >"$supacode_focused"
if command -v supacode >/dev/null 2>&1; then
  supacode worktree list --timeout 5 >"$supacode_worktrees" 2>/dev/null || : >"$supacode_worktrees"
  supacode worktree list --focused --timeout 5 >"$supacode_focused" 2>/dev/null || : >"$supacode_focused"
fi

candidates=$temporary_directory/candidates
blocked=$temporary_directory/blocked
: >"$candidates"
: >"$blocked"

while IFS="$(printf '\t')" read -r worktree_path branch worktree_locked; do
  [ -n "$worktree_path" ] || continue
  [ "$worktree_path" != "$primary_checkout" ] || continue

  reason=
  warning=
  manager=git
  local_oid=
  remote_oid=

  if [ "$branch" = "(detached)" ]; then
    reason="detached worktree has no branch group"
  else
    local_oid=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $2; exit }' "$local_branches")
    remote_oid=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $2; exit }' "$remote_branches")
    remote_protected=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $3; exit }' "$remote_branches")
    open_pr=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $3; exit }' "$open_prs")

    [ "$branch" != "$stable_branch" ] || reason="default branch cannot be selected"
    if [ "$remote_protected" = "true" ]; then
      reason="remote branch is protected"
    elif [ -n "$open_pr" ]; then
      reason="open pull request: $open_pr"
    elif [ -z "$local_oid" ]; then
      reason="local branch is unavailable"
    fi

    branch_worktree_count=$(awk -F '\t' -v branch="$branch" '$2 == branch { count++ } END { print count + 0 }' "$worktree_rows")
    if [ "$branch_worktree_count" -gt 1 ]; then
      reason="more than one worktree uses the branch"
    fi

    worktree_id=$(jq -nr --arg value "${worktree_path%/}/" '$value | @uri')
    if awk -F '\t' -v id="$worktree_id" '$1 == id { found = 1 } END { exit !found }' "$supacode_worktrees"; then
      manager=supacode
    elif [ "$worktree_locked" = "true" ]; then
      reason="worktree is locked outside Supacode"
    fi

    if [ -z "$reason" ]; then
      if worktree_status=$(git -C "$worktree_path" status --porcelain=v1 2>/dev/null); then
        [ -z "$worktree_status" ] || warning="worktree has uncommitted changes"
      else
        reason="worktree is unavailable"
      fi
    fi
    if [ -z "$reason" ] && awk -F '\t' -v id="$worktree_id" '$1 == id { found = 1 } END { exit !found }' "$supacode_focused"; then
      warning="${warning}${warning:+; }worktree is active in Supacode"
    fi
    if [ -z "$reason" ] && [ -n "$remote_oid" ] && [ "$local_oid" != "$remote_oid" ]; then
      warning="${warning}${warning:+; }local and remote tips differ"
    fi
    if [ -z "$reason" ] && ! git merge-base --is-ancestor "$local_oid" "$stable_oid" 2>/dev/null; then
      warning="${warning}${warning:+; }branch tip is not in $stable_branch"
    fi
  fi

  if [ -n "$reason" ]; then
    printf '%s\t%s\t%s\n' "$branch" "$worktree_path" "$reason" >>"$blocked"
  else
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$branch" "$worktree_path" "$manager" "$local_oid" "$remote_oid" "$warning" >>"$candidates"
  fi
done <"$worktree_rows"

selectable_count=$(wc -l <"$candidates" | tr -d ' ')
blocked_count=$(wc -l <"$blocked" | tr -d ' ')

if [ -z "$selected_branches" ]; then
  printf 'Repository cleanup candidates\n'
  printf 'Repository: %s\n' "$canonical_repository"
  printf 'Stable branch: %s at %s\n' "$stable_branch" "$stable_oid"
  printf 'Selectable groups: %s\n' "$selectable_count"
  awk -F '\t' '{
    remote = ($5 == "" ? "absent" : $5)
    warning = ($6 == "" ? "none" : $6)
    printf "- %s | %s | via %s | local %s | remote %s | warnings: %s\n", $1, $2, $3, $4, remote, warning
  }' "$candidates"
  printf 'Blocked groups: %s\n' "$blocked_count"
  awk -F '\t' '{ printf "- %s | %s | %s\n", $1, $2, $3 }' "$blocked"
  printf 'No changes were made. Select one or more branch groups to build a cleanup plan.\n'
  exit 0
fi

selected=$temporary_directory/selected
printf '%s\n' "$selected_branches" | awk 'NF' | sort -u >"$selected"
selected_count=$(wc -l <"$selected" | tr -d ' ')
[ "$selected_count" -gt 0 ] || usage

remove_worktrees=$temporary_directory/remove-worktrees
remove_local=$temporary_directory/remove-local
remove_remote=$temporary_directory/remove-remote
warnings=$temporary_directory/warnings
preserved=$temporary_directory/preserved
: >"$remove_worktrees"
: >"$remove_local"
: >"$remove_remote"
: >"$warnings"
: >"$preserved"

while IFS= read -r branch; do
  [ -n "$branch" ] || continue
  if blocked_reason=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $3; exit }' "$blocked") && [ -n "$blocked_reason" ]; then
    echo "clean.sh: branch $branch cannot be selected: $blocked_reason" >&2
    exit 2
  fi
  candidate=$(awk -F '\t' -v branch="$branch" '$1 == branch { print; exit }' "$candidates")
  [ -n "$candidate" ] || {
    echo "clean.sh: branch $branch is not a selectable worktree group" >&2
    exit 2
  }
  worktree_path=$(printf '%s\n' "$candidate" | cut -f2)
  manager=$(printf '%s\n' "$candidate" | cut -f3)
  local_oid=$(printf '%s\n' "$candidate" | cut -f4)
  remote_oid=$(printf '%s\n' "$candidate" | cut -f5)
  warning=$(printf '%s\n' "$candidate" | cut -f6-)
  printf '%s\t%s\t%s\n' "$worktree_path" "$branch" "$manager" >>"$remove_worktrees"
  printf '%s\t%s\n' "$branch" "$local_oid" >>"$remove_local"
  [ -z "$warning" ] || printf '%s\t%s\n' "$branch" "$warning" >>"$warnings"
  if [ -n "$remote_oid" ]; then
    if [ "$local_only" = "true" ]; then
      printf '%s\t%s\n' "$branch" "remote branch preserved by --local-only" >>"$preserved"
    else
      printf '%s\t%s\n' "$branch" "$remote_oid" >>"$remove_remote"
    fi
  fi
done <"$selected"

worktree_count=$(wc -l <"$remove_worktrees" | tr -d ' ')
local_count=$(wc -l <"$remove_local" | tr -d ' ')
remote_count=$(wc -l <"$remove_remote" | tr -d ' ')
unselected_count=$((selectable_count - selected_count))

printf 'Repository cleanup plan\n'
printf 'Repository: %s\n' "$canonical_repository"
printf 'Stable branch: %s at %s\n' "$stable_branch" "$stable_oid"
printf 'Mode: %s\n' "$([ "$local_only" = "true" ] && printf 'local only' || printf 'local and remote')"
printf 'Selected groups: %s\n' "$selected_count"
awk '{ printf "- %s\n", $0 }' "$selected"
printf 'Worktrees to remove: %s\n' "$worktree_count"
awk -F '\t' '{ printf "- %s [%s] via %s\n", $1, $2, $3 }' "$remove_worktrees"
printf 'Local branches to remove: %s\n' "$local_count"
awk -F '\t' '{ printf "- %s at %s\n", $1, $2 }' "$remove_local"
printf 'Remote branches to remove: %s\n' "$remote_count"
awk -F '\t' '{ printf "- %s at %s\n", $1, $2 }' "$remove_remote"
printf 'Warnings: %s\n' "$(wc -l <"$warnings" | tr -d ' ')"
awk -F '\t' '{ printf "- %s: %s\n", $1, $2 }' "$warnings"
printf 'Preserved: %s\n' "$(wc -l <"$preserved" | tr -d ' ')"
awk -F '\t' '{ printf "- %s: %s\n", $1, $2 }' "$preserved"
printf 'Unselected selectable groups: %s\n' "$unselected_count"

plan_token=$({
  printf 'operation\trepository-clean\nrepository\t%s\nstable\t%s\t%s\nlocal-only\t%s\n' \
    "$canonical_repository" "$stable_branch" "$stable_oid" "$local_only"
  sed 's/^/selected\t/' "$selected"
  sed 's/^/worktree\t/' "$remove_worktrees"
  sed 's/^/local\t/' "$remove_local"
  sed 's/^/remote\t/' "$remove_remote"
  sed 's/^/warning\t/' "$warnings"
  sed 's/^/preserved\t/' "$preserved"
} | hash_plan)

printf 'Confirmation token: %s\n' "$plan_token"
if [ -z "$confirmation" ]; then
  printf 'No changes were made. Confirm this exact plan before applying it.\n'
  exit 0
fi

[ "$confirmation" = "$plan_token" ] || {
  echo "clean.sh: the confirmation token does not match the current plan; review the new plan" >&2
  exit 2
}

while IFS="$(printf '\t')" read -r branch planned_oid; do
  [ -n "$branch" ] || continue
  encoded_branch=$(jq -nr --arg value "$branch" '$value | @uri')
  if ! remote_state=$(gh api "repos/$canonical_repository/branches/$encoded_branch" \
    --jq '[.commit.sha, .protected] | @tsv' 2>/dev/null); then
    echo "clean.sh: cannot revalidate remote branch $branch" >&2
    exit 2
  fi
  remote_oid=$(printf '%s\n' "$remote_state" | cut -f1)
  remote_protected=$(printf '%s\n' "$remote_state" | cut -f2)
  [ "$remote_oid" = "$planned_oid" ] && [ "$remote_protected" = "false" ] || {
    echo "clean.sh: remote branch $branch changed or became protected; no cleanup was applied" >&2
    exit 2
  }
done <"$remove_remote"

while IFS="$(printf '\t')" read -r worktree_path branch manager; do
  [ -n "$worktree_path" ] || continue
  if [ "$manager" = "supacode" ]; then
    worktree_id=$(jq -nr --arg value "${worktree_path%/}/" '$value | @uri')
    supacode worktree delete --worktree "$worktree_id" --background --timeout 30
  else
    git worktree remove --force "$worktree_path"
  fi
done <"$remove_worktrees"

git worktree prune

while IFS="$(printf '\t')" read -r branch planned_oid; do
  [ -n "$branch" ] || continue
  if current_ref=$(git rev-parse "refs/heads/$branch" 2>/dev/null); then
    [ "$current_ref" = "$planned_oid" ] || {
      echo "clean.sh: local branch $branch changed during cleanup" >&2
      exit 2
    }
    git branch -D -- "$branch" >/dev/null
  fi
done <"$remove_local"

while IFS="$(printf '\t')" read -r branch planned_oid; do
  [ -n "$branch" ] || continue
  current_ref=$(git ls-remote --heads origin "refs/heads/$branch" | awk '{ print $1 }')
  if [ -n "$current_ref" ]; then
    [ "$current_ref" = "$planned_oid" ] || {
      echo "clean.sh: remote branch $branch changed during cleanup" >&2
      exit 2
    }
    if ! push_error=$(git push origin --delete "$branch" 2>&1); then
      printf 'clean.sh: failed to delete remote branch %s\n%s\n' "$branch" "$push_error" >&2
      exit 2
    fi
  fi
done <"$remove_remote"

printf 'Repository cleanup applied: %s worktree(s), %s local branch(es), %s remote branch(es).\n' \
  "$worktree_count" "$local_count" "$remote_count"
