#!/bin/sh
set -eu

command_name=${GH_ISSUE_COMMAND:-clean.sh}

usage() {
  if [ "$command_name" = "clean.sh" ]; then
    echo "usage: clean.sh [--local-only] [--confirm TOKEN] OWNER/REPOSITORY|. ISSUE_NUMBER" >&2
    echo "       clean.sh [--local-only] [--select BRANCH]... [--confirm TOKEN] OWNER/REPOSITORY|." >&2
  else
    echo "usage: $command_name [--local-only] [--confirm TOKEN] OWNER/REPOSITORY|. ISSUE_NUMBER" >&2
  fi
  exit 64
}

if [ "$command_name" = "clean.sh" ]; then
  positional_count=0
  expect_value=false
  after_options=false
  for argument in "$@"; do
    if [ "$expect_value" = "true" ]; then
      expect_value=false
      continue
    fi
    if [ "$after_options" = "true" ]; then
      positional_count=$((positional_count + 1))
      continue
    fi
    case "$argument" in
      --confirm|--select) expect_value=true ;;
      --local-only|--cancel) ;;
      --) after_options=true ;;
      -*) ;;
      *) positional_count=$((positional_count + 1)) ;;
    esac
  done
  [ "$expect_value" = "false" ] || usage
  if [ "$positional_count" -eq 1 ]; then
    script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    exec "$script_directory/clean-repository.sh" "$@"
  fi
fi

operation=clean
local_only=false
confirmation=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --cancel)
      operation=cancel
      shift
      ;;
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
    echo "$command_name: $command is required" >&2
    exit 69
  }
done

hash_plan() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{ print $1 }'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{ print $1 }'
  else
    echo "$command_name: shasum or sha256sum is required" >&2
    return 69
  fi
}

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if ! root_json=$("$script_directory/query.sh" clean-root "$repository" "$number" 2>&1); then
  printf '%s: cannot resolve issue #%s\n%s\n' "$command_name" "$number" "$root_json" >&2
  exit 2
fi

issue_exists=$(printf '%s' "$root_json" | jq -r '.data.repository.issue != null')
[ "$issue_exists" = "true" ] || {
  echo "$command_name: issue #$number was not found" >&2
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
  echo "$command_name: GitHub returned an incomplete parent hierarchy" >&2
  exit 2
}
root_number=$(printf '%s' "$root_issue" | jq -r '.number')
root_title=$(printf '%s' "$root_issue" | jq -r '.title')

if ! tree_json=$("$script_directory/query.sh" clean-tree "$canonical_repository" "$root_number" 2>&1); then
  printf '%s: cannot resolve the issue tree rooted at #%s\n%s\n' "$command_name" "$root_number" "$tree_json" >&2
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
  echo "$command_name: GitHub returned incomplete cleanup data" >&2
  exit 2
fi

open_issues=$(jq -r '[.[] | select(.state == "OPEN") | "#\(.number) \(.title)"] | join(", ")' "$issues_file")
if [ "$operation" = "clean" ] && [ -n "$open_issues" ]; then
  echo "$command_name: the top-level effort still has open issues: $open_issues" >&2
  exit 2
fi

stable_branch=$(printf '%s' "$tree_json" | jq -er '.data.repository.defaultBranchRef.name')

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "$command_name: run this command from the primary checkout of $canonical_repository" >&2
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
  echo "$command_name: the current checkout is $current_repository, not $canonical_repository" >&2
  exit 2
}

worktrees_file=$temporary_directory/worktrees
git worktree list --porcelain >"$worktrees_file"
primary_checkout=$(awk '/^worktree / { print substr($0, 10); exit }' "$worktrees_file")
current_checkout=$(git rev-parse --show-toplevel)
current_branch=$(git branch --show-current)
[ "$current_checkout" = "$primary_checkout" ] && [ "$current_branch" = "$stable_branch" ] || {
  echo "$command_name: run this command from the primary checkout on $stable_branch" >&2
  exit 2
}
[ -z "$(git status --porcelain=v1)" ] || {
  echo "$command_name: the primary checkout has uncommitted changes" >&2
  exit 2
}

remote_branches=$temporary_directory/remote-branches
if ! gh api --paginate "repos/$canonical_repository/branches?per_page=100" \
  --jq '.[] | [.name, .commit.sha, .protected] | @tsv' >"$remote_branches"; then
  echo "$command_name: cannot read remote branch protection and tip data" >&2
  exit 2
fi

stable_oid=$(awk -F '\t' -v branch="$stable_branch" '$1 == branch { print $2; exit }' "$remote_branches")
[ -n "$stable_oid" ] || {
  echo "$command_name: remote stable branch $stable_branch was not found" >&2
  exit 2
}
current_oid=$(git rev-parse HEAD)
[ "$current_oid" = "$stable_oid" ] || {
  echo "$command_name: the primary checkout is not synchronized with origin/$stable_branch" >&2
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
  [.headRefName, (.number | tostring), .url] | @tsv
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
if [ "$operation" = "clean" ] && [ "$candidate_count" -gt 0 ] && [ "$root_candidate_count" -eq 0 ]; then
  echo "$command_name: cannot verify that top-level effort #$root_number reached $stable_branch" >&2
  exit 2
fi

if [ "$operation" = "clean" ] && [ "$root_candidate_count" -gt 0 ]; then
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
    echo "$command_name: top-level effort #$root_number has not reached $stable_branch" >&2
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
warnings=$temporary_directory/warnings
close_issues=$temporary_directory/close-issues
close_prs=$temporary_directory/close-prs
: >"$remove_worktrees"
: >"$remove_local"
: >"$remove_remote"
: >"$preserved"
: >"$warnings"
: >"$close_issues"
: >"$close_prs"

if [ "$operation" = "cancel" ]; then
  jq -r 'reverse[] | select(.state == "OPEN") | [(.number | tostring), .title] | @tsv' \
    "$issues_file" >"$close_issues"
  while IFS= read -r branch; do
    awk -F '\t' -v branch="$branch" '$1 == branch { print $2 "\t" $3 "\t" $1 }' \
      "$open_prs" >>"$close_prs"
  done <"$candidate_branches"
  sort -u "$close_prs" -o "$close_prs"
fi

while IFS= read -r branch; do
  [ -n "$branch" ] || continue
  local_oid=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $2; exit }' "$local_branches")
  remote_oid=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $2; exit }' "$remote_branches")
  remote_protected=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $3; exit }' "$remote_branches")
  open_pr=$(awk -F '\t' -v branch="$branch" '$1 == branch { print $3; exit }' "$open_prs")
  branch_worktrees=$(awk -F '\t' -v branch="$branch" '$2 == branch' "$worktree_rows")
  worktree_count=$(printf '%s\n' "$branch_worktrees" | awk 'NF { count++ } END { print count + 0 }')

  reason=
  warning=
  if [ -n "$open_pr" ]; then
    if [ "$operation" = "cancel" ]; then
      warning="open pull request will close: $open_pr"
    else
      reason="open pull request: $open_pr"
    fi
  fi
  if [ "$remote_protected" = "true" ]; then
    reason="remote branch is protected"
  elif [ -n "$local_oid" ] && [ -n "$remote_oid" ] && [ "$local_oid" != "$remote_oid" ]; then
    if [ "$operation" = "cancel" ]; then
      warning="${warning}${warning:+; }local and remote tips differ"
    else
      reason="local and remote tips differ"
    fi
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
      if [ "$operation" = "cancel" ]; then
        warning="${warning}${warning:+; }worktree is active in Supacode"
      else
        reason="worktree is active in Supacode: $worktree_path"
      fi
    fi
    if [ -z "$reason" ]; then
      if worktree_status=$(git -C "$worktree_path" status --porcelain=v1 2>/dev/null); then
        if [ -n "$worktree_status" ]; then
          if [ "$operation" = "cancel" ]; then
            warning="${warning}${warning:+; }worktree has uncommitted changes"
          else
            reason="worktree is dirty or unavailable: $worktree_path"
          fi
        fi
      else
        if [ "$operation" = "cancel" ]; then
          reason="worktree is unavailable: $worktree_path"
        else
          reason="worktree is dirty or unavailable: $worktree_path"
        fi
      fi
    fi
    if [ -z "$reason" ] && [ "$worktree_locked" = "true" ]; then
      if awk -F '\t' -v id="$worktree_id" '$1 == id { found = 1 } END { exit !found }' "$supacode_worktrees"; then
        worktree_manager=supacode
      else
        reason="worktree is locked outside Supacode: $worktree_path"
      fi
    fi
  fi

  branch_oid=$local_oid
  [ -n "$branch_oid" ] || branch_oid=$remote_oid
  if [ -z "$reason" ] && [ "$operation" = "clean" ]; then
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

  if [ -n "$warning" ]; then
    printf '%s\t%s\n' "$branch" "$warning" >>"$warnings"
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
issue_count=$(wc -l <"$close_issues" | tr -d ' ')
pr_count=$(wc -l <"$close_prs" | tr -d ' ')
action_count=$((worktree_count + local_count + remote_count + issue_count + pr_count))

if [ "$operation" = "cancel" ]; then
  printf 'Cancel plan: issue #%s resolves to #%s %s\n' "$number" "$root_number" "$root_title"
  printf 'Issues to close as Not planned: %s\n' "$issue_count"
  awk -F '\t' '{ printf "- #%s %s\n", $1, $2 }' "$close_issues"
  printf 'Pull requests to close: %s\n' "$pr_count"
  awk -F '\t' '{ printf "- #%s %s [%s]\n", $1, $2, $3 }' "$close_prs"
else
  printf 'Clean plan: issue #%s resolves to #%s %s\n' "$number" "$root_number" "$root_title"
fi
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
printf 'Warnings: %s\n' "$(wc -l <"$warnings" | tr -d ' ')"
awk -F '\t' '{ printf "- %s: %s\n", $1, $2 }' "$warnings"

if [ "$action_count" -eq 0 ]; then
  if [ "$operation" = "cancel" ]; then
    printf 'Nothing is eligible for cancellation.\n'
  else
    printf 'Nothing is eligible for cleanup.\n'
  fi
  exit 0
fi

plan_token=$({
  printf 'operation\t%s\nrepository\t%s\nroot\t%s\nstable\t%s\t%s\nlocal-only\t%s\n' \
    "$operation" "$canonical_repository" "$root_number" "$stable_branch" "$stable_oid" "$local_only"
  sed 's/^/issue\t/' "$close_issues"
  sed 's/^/pr\t/' "$close_prs"
  sed 's/^/worktree\t/' "$remove_worktrees"
  sed 's/^/local\t/' "$remove_local"
  sed 's/^/remote\t/' "$remove_remote"
  sed 's/^/preserved\t/' "$preserved"
  sed 's/^/warning\t/' "$warnings"
} | hash_plan)

printf 'Confirmation token: %s\n' "$plan_token"
if [ -z "$confirmation" ]; then
  printf 'No changes were made. Confirm this exact plan before applying it.\n'
  exit 0
fi

[ "$confirmation" = "$plan_token" ] || {
  echo "$command_name: the confirmation token does not match the current plan; review the new plan" >&2
  exit 2
}

while IFS="$(printf '\t')" read -r branch planned_oid; do
  [ -n "$branch" ] || continue
  encoded_branch=$(jq -nr --arg value "$branch" '$value | @uri')
  if ! remote_state=$(gh api "repos/$canonical_repository/branches/$encoded_branch" \
    --jq '[.commit.sha, .protected] | @tsv' 2>/dev/null); then
    echo "$command_name: cannot revalidate remote branch $branch" >&2
    exit 2
  fi
  remote_oid=$(printf '%s\n' "$remote_state" | cut -f1)
  remote_protected=$(printf '%s\n' "$remote_state" | cut -f2)
  [ "$remote_oid" = "$planned_oid" ] && [ "$remote_protected" = "false" ] || {
    echo "$command_name: remote branch $branch changed or became protected; no cleanup was applied" >&2
    exit 2
  }
done <"$remove_remote"

while IFS="$(printf '\t')" read -r pr_number pr_url branch; do
  [ -n "$pr_number" ] || continue
  if ! close_error=$(gh pr close "$pr_number" --repo "$canonical_repository" 2>&1); then
    printf '%s: failed to close pull request #%s\n%s\n' "$command_name" "$pr_number" "$close_error" >&2
    exit 2
  fi
done <"$close_prs"

while IFS="$(printf '\t')" read -r issue_number issue_title; do
  [ -n "$issue_number" ] || continue
  if ! close_error=$(gh issue close "$issue_number" --repo "$canonical_repository" --reason 'not planned' 2>&1); then
    printf '%s: failed to close issue #%s\n%s\n' "$command_name" "$issue_number" "$close_error" >&2
    exit 2
  fi
done <"$close_issues"

while IFS="$(printf '\t')" read -r worktree_path branch manager; do
  [ -n "$worktree_path" ] || continue
  if [ "$manager" = "supacode" ]; then
    worktree_id=$(jq -nr --arg value "${worktree_path%/}/" '$value | @uri')
    supacode worktree delete --worktree "$worktree_id" --background --timeout 30
  else
    if [ "$operation" = "cancel" ]; then
      git worktree remove --force "$worktree_path"
    else
      git worktree remove "$worktree_path"
    fi
  fi
done <"$remove_worktrees"

git worktree prune

while IFS="$(printf '\t')" read -r branch planned_oid; do
  [ -n "$branch" ] || continue
  if current_ref=$(git rev-parse "refs/heads/$branch" 2>/dev/null); then
    [ "$current_ref" = "$planned_oid" ] || {
      echo "$command_name: local branch $branch changed during cleanup" >&2
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
      echo "$command_name: remote branch $branch changed during cleanup" >&2
      exit 2
    }
    if ! push_error=$(git push origin --delete "$branch" 2>&1); then
      printf '%s: failed to delete remote branch %s\n%s\n' "$command_name" "$branch" "$push_error" >&2
      exit 2
    fi
  fi
done <"$remove_remote"

if [ "$operation" = "cancel" ]; then
  printf 'Cancellation applied: %s issue(s), %s pull request(s), %s worktree(s), %s local branch(es), %s remote branch(es).\n' \
    "$issue_count" "$pr_count" "$worktree_count" "$local_count" "$remote_count"
else
  printf 'Cleanup applied: %s worktree(s), %s local branch(es), %s remote branch(es).\n' \
    "$worktree_count" "$local_count" "$remote_count"
fi
