#!/bin/sh
set -eu

usage() {
  echo "usage: finish.sh [--dry-run] [--base BRANCH] OWNER/REPOSITORY|. ISSUE_NUMBER" >&2
  exit 64
}

dry_run=false
base_override=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    --base)
      [ "$#" -ge 2 ] || usage
      base_override=$2
      shift 2
      ;;
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

command -v jq >/dev/null 2>&1 || {
  echo "finish.sh: jq is required" >&2
  exit 69
}

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
finish_json=$("$script_directory/query.sh" finish "$repository" "$number")

issue_exists=$(printf '%s' "$finish_json" | jq -r '.data.repository.issue != null')
[ "$issue_exists" = "true" ] || {
  echo "finish.sh: issue #$number was not found" >&2
  exit 2
}

canonical_repository=$(printf '%s' "$finish_json" | jq -er '.data.repository.nameWithOwner')
issue_state=$(printf '%s' "$finish_json" | jq -r '.data.repository.issue.state')
issue_title=$(printf '%s' "$finish_json" | jq -r '.data.repository.issue.title')
issue_url=$(printf '%s' "$finish_json" | jq -r '.data.repository.issue.url')
default_branch=$(printf '%s' "$finish_json" | jq -er '.data.repository.defaultBranchRef.name')
child_total=$(printf '%s' "$finish_json" | jq -r '.data.repository.issue.subIssues.totalCount')
child_loaded=$(printf '%s' "$finish_json" | jq -r '.data.repository.issue.subIssues.nodes | length')

if [ "$issue_state" != "OPEN" ]; then
  printf 'Issue #%s is already %s: %s\n' "$number" "$issue_state" "$issue_url"
  exit 0
fi

[ "$child_total" -eq "$child_loaded" ] || {
  echo "finish.sh: GitHub returned $child_loaded of $child_total direct children" >&2
  exit 2
}

open_children=$(printf '%s' "$finish_json" | jq -r '[.data.repository.issue.subIssues.nodes[] | select(.state == "OPEN")] | length')
if [ "$open_children" -gt 0 ]; then
  printf 'Issue #%s still has %s open direct child issue(s).\n' "$number" "$open_children" >&2
  exit 2
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "finish.sh: run this command from a checkout of $canonical_repository" >&2
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
  echo "finish.sh: the current checkout is $current_repository, not $canonical_repository" >&2
  exit 2
}

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-finish.XXXXXX")
trap 'find "$temporary_directory" -type f -delete 2>/dev/null || true; rmdir "$temporary_directory" 2>/dev/null || true' EXIT HUP INT TERM

worktrees_file=$temporary_directory/worktrees
matches_file=$temporary_directory/matches

git worktree list --porcelain >"$worktrees_file"
awk -v number="$number" '
  function emit() {
    if (path != "" && branch ~ ("(^|[-_/])" number "([-_/]|$)")) {
      print path "\t" branch
    }
  }
  /^worktree / {
    path = substr($0, 10)
    next
  }
  /^branch refs\/heads\// {
    branch = substr($0, 19)
    next
  }
  /^$/ {
    emit()
    path = ""
    branch = ""
  }
  END { emit() }
' "$worktrees_file" >"$matches_file"

match_count=$(wc -l <"$matches_file" | tr -d ' ')
current_root=$(git rev-parse --show-toplevel)
current_branch=$(git branch --show-current)

selected=
if printf '%s' "$current_branch" | grep -Eq "(^|[-_/])${number}([-_/]|$)"; then
  selected=$(awk -F '\t' -v path="$current_root" '$1 == path { print; exit }' "$matches_file")
fi

if [ -z "$selected" ] && [ "$match_count" -eq 1 ]; then
  selected=$(cat "$matches_file")
fi

if [ -z "$selected" ]; then
  if [ "$match_count" -eq 0 ]; then
    echo "finish.sh: no worktree matches issue #$number" >&2
  else
    echo "finish.sh: more than one worktree matches issue #$number" >&2
    cat "$matches_file" >&2
  fi
  exit 2
fi

worktree_path=$(printf '%s' "$selected" | cut -f1)
branch=$(printf '%s' "$selected" | cut -f2)

dirty=$(git -C "$worktree_path" status --porcelain=v1 --untracked-files=all)
conflicts=$(git -C "$worktree_path" diff --name-only --diff-filter=U --)
if [ -n "$conflicts" ]; then
  printf 'Issue #%s has unresolved conflicts in %s.\n' "$number" "$worktree_path" >&2
  printf '%s\n' "$conflicts" >&2
  exit 2
fi

pr_json=$(gh pr list \
  --repo "$canonical_repository" \
  --head "$branch" \
  --state all \
  --limit 2 \
  --json number,title,state,isDraft,url,baseRefName,headRefName)
pr_count=$(printf '%s' "$pr_json" | jq -r 'length')

if [ "$pr_count" -gt 1 ]; then
  echo "finish.sh: more than one pull request matches branch $branch" >&2
  exit 2
fi

pr_state=none
pr_url=none
base_branch=
if [ "$pr_count" -eq 1 ]; then
  pr_state=$(printf '%s' "$pr_json" | jq -r '.[0].state')
  pr_url=$(printf '%s' "$pr_json" | jq -r '.[0].url')
  base_branch=$(printf '%s' "$pr_json" | jq -r '.[0].baseRefName')

  if [ "$pr_state" = "MERGED" ]; then
    if [ -n "$dirty" ]; then
      printf 'Issue #%s has uncommitted work after its pull request merged.\n' "$number" >&2
      printf '%s\n' "$dirty" >&2
      exit 2
    fi
    if [ "$dry_run" = "true" ]; then
      printf 'Issue #%s would close as completed because %s is merged.\n' "$number" "$pr_url"
    else
      gh issue close "$number" --repo "$canonical_repository" --reason completed >/dev/null
      printf 'Issue #%s closed as completed because %s is merged.\n' "$number" "$pr_url"
    fi
    exit 0
  fi

  if [ "$pr_state" = "CLOSED" ]; then
    echo "finish.sh: branch $branch has a closed, unmerged pull request: $pr_url" >&2
    exit 2
  fi
fi

if [ "$child_total" -gt 0 ]; then
  child_pr_json=$(gh pr list \
    --repo "$canonical_repository" \
    --base "$branch" \
    --state open \
    --limit 2 \
    --json number,title,state,isDraft,url,baseRefName,headRefName)
  child_pr_count=$(printf '%s' "$child_pr_json" | jq -r 'length')
  if [ "$child_pr_count" -gt 0 ]; then
    echo "finish.sh: issue #$number has an open pull request that targets $branch" >&2
    printf '%s' "$child_pr_json" | jq -r '.[] | "#\(.number) \(.title): \(.url)"' >&2
    exit 2
  fi
fi

if [ -z "$base_branch" ]; then
  if [ -n "$base_override" ]; then
    base_branch=$base_override
  else
    config=$("$script_directory/start-config.sh" "$canonical_repository")
    if [ "$child_total" -eq 0 ]; then
      base_branch=$(printf '%s' "$config" | jq -r '.taskBaseBranch // empty')
    fi
    parent_number=$(printf '%s' "$finish_json" | jq -r '.data.repository.issue.parent.number // empty')
  fi
  if [ -z "${parent_number:-}" ] && [ -z "$base_branch" ]; then
    base_branch=$default_branch
  elif [ -z "$base_branch" ]; then
    parent_candidates=$temporary_directory/parent-candidates
    {
      awk -F '\t' '{ print $2 }' "$matches_file" 2>/dev/null || true
      git for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin
    } | sed 's#^origin/##' | grep -E "(^|[-_/])${parent_number}([-_/]|$)" | sort -u >"$parent_candidates" || true
    parent_count=$(wc -l <"$parent_candidates" | tr -d ' ')
    if [ "$parent_count" -ne 1 ]; then
      echo "finish.sh: cannot resolve one base branch for parent issue #$parent_number; rerun with --base BRANCH" >&2
      cat "$parent_candidates" >&2
      exit 2
    fi
    base_branch=$(cat "$parent_candidates")
  fi
fi

git check-ref-format "refs/heads/$base_branch" >/dev/null || {
  echo "finish.sh: invalid base branch $base_branch" >&2
  exit 2
}
if git -C "$worktree_path" ls-remote --exit-code --heads origin "refs/heads/$base_branch" >"$temporary_directory/remote-base"; then
  if ! git -C "$worktree_path" fetch --no-tags origin "+refs/heads/$base_branch:refs/remotes/origin/$base_branch"; then
    echo "finish.sh: cannot fetch remote base branch $base_branch" >&2
    exit 2
  fi
  base_ref=refs/remotes/origin/$base_branch
else
  remote_status=$?
  if [ "$remote_status" -ne 2 ]; then
    echo "finish.sh: cannot inspect remote base branch $base_branch" >&2
    exit 2
  fi
  if git -C "$worktree_path" rev-parse --verify --quiet "refs/heads/${base_branch}^{commit}" >/dev/null; then
    base_ref=refs/heads/$base_branch
  else
    echo "finish.sh: base branch $base_branch is unavailable in $worktree_path" >&2
    exit 2
  fi
fi

if git -C "$worktree_path" diff --quiet "${base_ref}...HEAD" --; then
  has_changes=false
else
  diff_status=$?
  [ "$diff_status" -eq 1 ] || {
    echo "finish.sh: Git could not compare $branch with $base_ref" >&2
    exit "$diff_status"
  }
  has_changes=true
fi

if [ "$has_changes" = "false" ] && [ -z "$dirty" ]; then
  if [ "$pr_state" = "OPEN" ]; then
    echo "finish.sh: open pull request $pr_url conflicts with a no-change branch" >&2
    exit 2
  fi

  if [ "$dry_run" = "true" ]; then
    printf 'Issue #%s would close as completed.\n' "$number"
  else
    gh issue close "$number" --repo "$canonical_repository" --reason completed >/dev/null
    printf 'Issue #%s closed as completed.\n' "$number"
  fi
  printf 'No commit, push, or pull request is necessary.\n'
  printf 'Worktree: %s\n' "$worktree_path"
  printf 'Branch: %s\n' "$branch"
  printf 'Base: %s\n' "$base_branch"
  exit 0
fi

changed_paths=$(git -C "$worktree_path" diff --name-only "${base_ref}...HEAD" --)
printf 'Issue #%s has changes that require review and validation.\n' "$number"
printf 'Title: %s\n' "$issue_title"
printf 'Worktree: %s\n' "$worktree_path"
printf 'Branch: %s\n' "$branch"
printf 'Base: %s\n' "$base_branch"
printf 'Pull request: %s\n' "$pr_url"
printf 'Changed paths:\n'
if [ -n "$changed_paths" ]; then
  printf 'Committed paths:\n'
  printf '%s\n' "$changed_paths" | sed 's/^/- /'
fi
if [ -n "$dirty" ]; then
  printf 'Uncommitted paths (Git status):\n'
  printf '%s\n' "$dirty"
fi
printf 'Next: review and validate these changes, then commit, push, and prepare the pull request.\n'
