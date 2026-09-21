#!/bin/sh
set -eu

usage() {
  echo "usage: clean.sh [--local-only] [--confirm TOKEN] OWNER/REPOSITORY|. ISSUE_NUMBER" >&2
  exit 64
}

local_only=false
confirmation=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --local-only)
      local_only=true
      shift
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

[ "$#" -eq 2 ] || usage

repository=$1
number=$2
case "$number" in
  ''|*[!0-9]*) usage ;;
esac
[ "$number" -gt 0 ] || usage

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

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if ! root_json=$("$script_directory/query.sh" clean-root "$repository" "$number" 2>&1); then
  printf 'clean.sh: cannot resolve issue #%s\n%s\n' "$number" "$root_json" >&2
  exit 2
fi

issue_exists=$(printf '%s' "$root_json" | jq -r '.data.repository.issue != null')
[ "$issue_exists" = "true" ] || {
  echo "clean.sh: issue #$number was not found" >&2
  exit 2
}

canonical_repository=$(printf '%s' "$root_json" | jq -er '.data.repository.nameWithOwner')
root_issue=$(printf '%s' "$root_json" | jq -ce '
  def hierarchy:
    [.] + (if (.parent? | type) == "object" then (.parent | hierarchy) else [] end);
  (.data.repository.issue | hierarchy) as $hierarchy |
  if any($hierarchy[]; (.state // "") == "") then
    error("GitHub truncated the parent hierarchy")
  else $hierarchy[-1] end
') || {
  echo "clean.sh: GitHub returned an incomplete parent hierarchy" >&2
  exit 2
}
root_number=$(printf '%s' "$root_issue" | jq -r '.number')
root_title=$(printf '%s' "$root_issue" | jq -r '.title')

if ! tree_json=$("$script_directory/query.sh" clean-tree "$canonical_repository" "$root_number" 2>&1); then
  printf 'clean.sh: cannot resolve the issue tree rooted at #%s\n%s\n' "$root_number" "$tree_json" >&2
  exit 2
fi

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-clean.XXXXXX")
trap 'find "$temporary_directory" -type f -delete 2>/dev/null || true; rmdir "$temporary_directory" 2>/dev/null || true' EXIT HUP INT TERM

issues_file=$temporary_directory/issues.json
if ! printf '%s' "$tree_json" | jq -ce '
  def descendants:
    [.] + (((.subIssues.nodes? // []) | map(descendants) | add) // []);
  (.data.repository.issue | descendants) as $issues |
  if .data.repository.issue == null then
    error("root issue not found")
  elif .data.repository.openPullRequests.totalCount >
       (.data.repository.openPullRequests.nodes | length) then
    error("GitHub truncated the open pull request list")
  elif any($issues[];
    .subIssues.totalCount > ((.subIssues.nodes? // []) | length)) then
    error("GitHub truncated the issue tree")
  elif any($issues[];
    .linkedBranches.totalCount > (.linkedBranches.nodes | length)) then
    error("GitHub truncated a linked branch list")
  else $issues end
' >"$issues_file"; then
  echo "clean.sh: GitHub returned incomplete cleanup data" >&2
  exit 2
fi

open_issues=$(jq -r '[.[] | select(.state == "OPEN") | "#\(.number) \(.title)"] | join(", ")' "$issues_file")
[ -z "$open_issues" ] || {
  echo "clean.sh: the top-level effort still has open issues: $open_issues" >&2
  exit 2
}

stable_branch=$(printf '%s' "$tree_json" | jq -er '.data.repository.defaultBranchRef.name')

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

worktree_rows=$temporary_directory/worktree-rows
awk '
  function emit() {
    if (path != "" && branch != "") print path "\t" branch "\t" locked
  }
  /^worktree / { path = substr($0, 10); branch = ""; locked = "false"; next }
  /^branch refs\/heads\// { branch = substr($0, 19); next }
  /^locked/ { locked = "true"; next }
  /^$/ { emit(); path = ""; branch = ""; locked = "false" }
  END { emit() }
' "$worktrees_file" >"$worktree_rows"

issue_numbers=$temporary_directory/issue-numbers
jq -r '.[].number' "$issues_file" >"$issue_numbers"
numbers_pattern=$(paste -sd '|' "$issue_numbers")

linked_branches=$temporary_directory/linked-branches
jq -r --arg repository "$canonical_repository" '
  .[] | .linkedBranches.nodes[] |
  select(.ref.repository.nameWithOwner == $repository) |
  .ref.name
' "$issues_file" | sort -u >"$linked_branches"

all_branches=$temporary_directory/all-branches
{
  cut -f1 "$local_branches"
  cut -f1 "$remote_branches"
} | sort -u >"$all_branches"

candidate_branches=$temporary_directory/candidate-branches
: >"$candidate_branches"
while IFS= read -r branch; do
  [ "$branch" != "$stable_branch" ] || continue
  if grep -Fqx "$branch" "$linked_branches" ||
     printf '%s\n' "$branch" | grep -Eq "(^|[-_/])(${numbers_pattern})([-_/]|$)"; then
    printf '%s\n' "$branch" >>"$candidate_branches"
  fi
done <"$all_branches"

open_prs=$temporary_directory/open-prs
printf '%s' "$tree_json" | jq -r '
  .data.repository.openPullRequests.nodes[] |
  [.headRefName, .url] | @tsv
' >"$open_prs"

root_linked_branches=$temporary_directory/root-linked-branches
jq -r --arg repository "$canonical_repository" '
  .[0].linkedBranches.nodes[] |
  select(.ref.repository.nameWithOwner == $repository) |
  .ref.name
' "$issues_file" | sort -u >"$root_linked_branches"

root_candidates=$temporary_directory/root-candidates
: >"$root_candidates"
while IFS= read -r branch; do
  if grep -Fqx "$branch" "$root_linked_branches" ||
     printf '%s\n' "$branch" | grep -Eq "(^|[-_/])${root_number}([-_/]|$)"; then
    printf '%s\n' "$branch" >>"$root_candidates"
  fi
done <"$candidate_branches"

candidate_count=$(wc -l <"$candidate_branches" | tr -d ' ')
root_candidate_count=$(wc -l <"$root_candidates" | tr -d ' ')
if [ "$candidate_count" -gt 0 ] && [ "$root_candidate_count" -eq 0 ]; then
  echo "clean.sh: cannot verify that top-level effort #$root_number reached $stable_branch" >&2
  exit 2
fi

if [ "$root_candidate_count" -gt 0 ]; then
  root_reached_stable=false
  while IFS= read -r branch; do
    [ -n "$branch" ] || continue
    if awk -F '\t' -v branch="$branch" '$1 == branch { found = 1 } END { exit !found }' "$open_prs"; then
      continue
    fi
    local_oid=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $2; exit }' "$local_branches")
    remote_oid=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $2; exit }' "$remote_branches")
    if [ -n "$local_oid" ] && [ -n "$remote_oid" ] && [ "$local_oid" != "$remote_oid" ]; then
      continue
    fi
    branch_oid=$local_oid
    [ -n "$branch_oid" ] || branch_oid=$remote_oid
    if git cat-file -e "${branch_oid}^{commit}" 2>/dev/null &&
       git merge-base --is-ancestor "$branch_oid" "$stable_oid" 2>/dev/null; then
      root_reached_stable=true
      break
    fi
    if merged_prs=$(gh pr list --repo "$canonical_repository" --head "$branch" --state merged --limit 2 --json url,headRefOid 2>/dev/null) &&
       printf '%s' "$merged_prs" | jq -e --arg oid "$branch_oid" 'any(.[]; .headRefOid == $oid)' >/dev/null; then
      root_reached_stable=true
      break
    fi
  done <"$root_candidates"
  [ "$root_reached_stable" = "true" ] || {
    echo "clean.sh: top-level effort #$root_number has not reached $stable_branch" >&2
    exit 2
  }
fi

supacode_worktrees=$temporary_directory/supacode-worktrees
supacode_focused=$temporary_directory/supacode-focused
: >"$supacode_worktrees"
: >"$supacode_focused"
if command -v supacode >/dev/null 2>&1; then
  supacode worktree list --timeout 5 >"$supacode_worktrees" 2>/dev/null || : >"$supacode_worktrees"
  supacode worktree list --focused --timeout 5 >"$supacode_focused" 2>/dev/null || : >"$supacode_focused"
fi

remove_worktrees=$temporary_directory/remove-worktrees
remove_local=$temporary_directory/remove-local
remove_remote=$temporary_directory/remove-remote
preserved=$temporary_directory/preserved
: >"$remove_worktrees"
: >"$remove_local"
: >"$remove_remote"
: >"$preserved"

while IFS= read -r branch; do
  [ -n "$branch" ] || continue
  local_oid=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $2; exit }' "$local_branches")
  remote_oid=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $2; exit }' "$remote_branches")
  remote_protected=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $3; exit }' "$remote_branches")
  open_pr=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $2; exit }' "$open_prs")
  branch_worktrees=$(awk -F '\t' -v branch="$branch" '$2 == branch' "$worktree_rows")
  worktree_count=$(printf '%s\n' "$branch_worktrees" | awk 'NF { count++ } END { print count + 0 }')

  reason=
  if [ -n "$open_pr" ]; then
    reason="open pull request: $open_pr"
  elif [ "$remote_protected" = "true" ]; then
    reason="remote branch is protected"
  elif [ -n "$local_oid" ] && [ -n "$remote_oid" ] && [ "$local_oid" != "$remote_oid" ]; then
    reason="local and remote tips differ"
  elif [ "$worktree_count" -gt 1 ]; then
    reason="more than one worktree uses the branch"
  fi

  worktree_path=
  worktree_locked=false
  worktree_manager=git
  if [ "$worktree_count" -eq 1 ]; then
    worktree_path=$(printf '%s\n' "$branch_worktrees" | cut -f1)
    worktree_locked=$(printf '%s\n' "$branch_worktrees" | cut -f3)
    worktree_id=$(jq -nr --arg value "${worktree_path%/}/" '$value | @uri')
    if [ "$worktree_path" = "$current_checkout" ]; then
      reason="branch is active in the current checkout"
    elif awk -F '\t' -v id="$worktree_id" '$1 == id { found = 1 } END { exit !found }' "$supacode_focused"; then
      reason="worktree is active in Supacode: $worktree_path"
    elif [ -n "$(git -C "$worktree_path" status --porcelain=v1 2>/dev/null || printf unavailable)" ]; then
      reason="worktree is dirty or unavailable: $worktree_path"
    elif [ "$worktree_locked" = "true" ]; then
      if awk -F '\t' -v id="$worktree_id" '$1 == id { found = 1 } END { exit !found }' "$supacode_worktrees"; then
        worktree_manager=supacode
      else
        reason="worktree is locked outside Supacode: $worktree_path"
      fi
    fi
  fi

  branch_oid=$local_oid
  [ -n "$branch_oid" ] || branch_oid=$remote_oid
  if [ -z "$reason" ]; then
    reached_stable=false
    if git cat-file -e "${branch_oid}^{commit}" 2>/dev/null &&
       git merge-base --is-ancestor "$branch_oid" "$stable_oid" 2>/dev/null; then
      reached_stable=true
    else
      if merged_prs=$(gh pr list --repo "$canonical_repository" --head "$branch" --state merged --limit 2 --json url,headRefOid 2>/dev/null); then
        if printf '%s' "$merged_prs" | jq -e --arg oid "$branch_oid" 'any(.[]; .headRefOid == $oid)' >/dev/null; then
          reached_stable=true
        fi
      fi
    fi
    if [ "$reached_stable" != "true" ]; then
      reason="branch tip is not verified in $stable_branch"
    fi
  fi

  if [ -n "$reason" ]; then
    printf '%s\t%s\n' "$branch" "$reason" >>"$preserved"
    continue
  fi

  if [ -n "$worktree_path" ]; then
    printf '%s\t%s\t%s\n' "$worktree_path" "$branch" "$worktree_manager" >>"$remove_worktrees"
  fi
  if [ -n "$local_oid" ]; then
    printf '%s\t%s\n' "$branch" "$local_oid" >>"$remove_local"
  fi
  if [ -n "$remote_oid" ]; then
    if [ "$local_only" = "true" ]; then
      printf '%s\t%s\n' "$branch" "remote branch preserved by --local-only" >>"$preserved"
    else
      printf '%s\t%s\n' "$branch" "$remote_oid" >>"$remove_remote"
    fi
  fi
done <"$candidate_branches"

worktree_count=$(wc -l <"$remove_worktrees" | tr -d ' ')
local_count=$(wc -l <"$remove_local" | tr -d ' ')
remote_count=$(wc -l <"$remove_remote" | tr -d ' ')
action_count=$((worktree_count + local_count + remote_count))

printf 'Clean plan: issue #%s resolves to #%s %s\n' "$number" "$root_number" "$root_title"
printf 'Repository: %s\n' "$canonical_repository"
printf 'Stable branch: %s at %s\n' "$stable_branch" "$stable_oid"
printf 'Mode: %s\n' "$([ "$local_only" = "true" ] && printf 'local only' || printf 'local and remote')"

printf 'Worktrees to remove: %s\n' "$worktree_count"
awk -F '\t' '{ printf "- %s [%s] via %s\n", $1, $2, $3 }' "$remove_worktrees"
printf 'Local branches to remove: %s\n' "$local_count"
awk -F '\t' '{ printf "- %s at %s\n", $1, $2 }' "$remove_local"
printf 'Remote branches to remove: %s\n' "$remote_count"
awk -F '\t' '{ printf "- %s at %s\n", $1, $2 }' "$remove_remote"
printf 'Preserved: %s\n' "$(wc -l <"$preserved" | tr -d ' ')"
awk -F '\t' '{ printf "- %s: %s\n", $1, $2 }' "$preserved"

if [ "$action_count" -eq 0 ]; then
  printf 'Nothing is eligible for cleanup.\n'
  exit 0
fi

plan_token=$({
  printf 'repository\t%s\nroot\t%s\nstable\t%s\t%s\nlocal-only\t%s\n' \
    "$canonical_repository" "$root_number" "$stable_branch" "$stable_oid" "$local_only"
  sed 's/^/worktree\t/' "$remove_worktrees"
  sed 's/^/local\t/' "$remove_local"
  sed 's/^/remote\t/' "$remove_remote"
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
    git worktree remove "$worktree_path"
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

printf 'Cleanup applied: %s worktree(s), %s local branch(es), %s remote branch(es).\n' \
  "$worktree_count" "$local_count" "$remote_count"
