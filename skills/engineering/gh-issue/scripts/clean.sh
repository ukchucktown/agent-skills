#!/bin/sh
set -eu

command_name=${GH_ISSUE_COMMAND:-clean.sh}

usage() {
  if [ "$command_name" = "clean.sh" ]; then
    echo "usage: clean.sh [--local-only] [--confirm TOKEN] OWNER/REPOSITORY|. ISSUE_NUMBER" >&2
    echo "       clean.sh [--local-only] [--force] [--all | --select BRANCH...] [--confirm TOKEN] OWNER/REPOSITORY|." >&2
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
      --local-only|--cancel|--all|--force) ;;
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
references=$script_directory/../references
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
owner=${canonical_repository%%/*}
name=${canonical_repository#*/}
default_branch=$(printf '%s' "$root_json" | jq -er '.data.repository.defaultBranchRef.name')

# Cancel abandons the whole top-level effort. Clean covers the issue and its
# sub-issues only, so it can run while the effort stays open.
root_number=$number
root_title=$(printf '%s' "$root_json" | jq -r '.data.repository.issue.title')
if [ "$operation" = "cancel" ]; then
  # Cancel closes issues by number in this repository, so the hierarchy must
  # stay in this repository.
  foreign_issue=$(printf '%s' "$root_json" | jq -r --arg repository "$canonical_repository" '
    def hierarchy:
      [.] + (if (.parent? | type) == "object" then (.parent | hierarchy) else [] end);
    [.data.repository.issue | hierarchy | .[] |
      select(.repository != null and .repository.nameWithOwner != $repository)] |
    first // empty | "\(.repository.nameWithOwner)#\(.number)"
  ')
  [ -z "$foreign_issue" ] || {
    echo "$command_name: cancel works in one repository, but the parents of #$number include $foreign_issue" >&2
    exit 2
  }
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
fi

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-clean.XXXXXX")
trap 'find "$temporary_directory" -type f -delete 2>/dev/null || true; rmdir "$temporary_directory" 2>/dev/null || true' EXIT HUP INT TERM

if ! repository_json=$(gh api graphql \
  -F "owner=$owner" \
  -F "name=$name" \
  -F "query=@$references/clean-repository.graphql" 2>&1); then
  printf '%s: cannot read the open pull requests\n%s\n' "$command_name" "$repository_json" >&2
  exit 2
fi
printf '%s' "$repository_json" | jq -e '
  .data.repository.openPullRequests.totalCount <=
  (.data.repository.openPullRequests.nodes | length)
' >/dev/null || {
  echo "$command_name: GitHub truncated the open pull request list" >&2
  exit 2
}

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
[ "$current_checkout" = "$primary_checkout" ] || {
  echo "$command_name: run this command from the primary checkout of $canonical_repository" >&2
  exit 2
}
# The stable branch is the branch that the primary checkout stays on.
[ -n "$current_branch" ] || {
  echo "$command_name: the primary checkout has no current branch" >&2
  exit 2
}
stable_branch=$current_branch
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

# Clean and cancel never remove the stable branch or the default branch.
all_branches=$temporary_directory/all-branches
{
  cut -f1 "$local_branches"
  cut -f1 "$remote_branches"
} | awk -v stable="$stable_branch" -v default_branch="$default_branch" \
  'NF && $0 != stable && $0 != default_branch' | sort -u >"$all_branches"

open_prs=$temporary_directory/open-prs
printf '%s' "$repository_json" | jq -r '
  .data.repository.openPullRequests.nodes[] |
  [.headRefName, (.number | tostring), .url] | @tsv
' >"$open_prs"

issues_file=$temporary_directory/issues.json
candidate_branches=$temporary_directory/candidate-branches
branch_issues=$temporary_directory/branch-issues
: >"$candidate_branches"
: >"$branch_issues"

if [ "$operation" = "cancel" ]; then
  # Cancel must close open issues that have no branch, so it reads the full
  # tree. Each sub-issue list is read page by page until it is complete.
  tree_lines=$temporary_directory/tree-lines
  pending=$temporary_directory/pending
  visited=$temporary_directory/visited
  : >"$tree_lines"
  : >"$visited"
  printf '%s\n' "$root_number" >"$pending"
  root_recorded=false
  while [ -s "$pending" ]; do
    parent=$(sed -n '1p' "$pending")
    sed '1d' "$pending" >"$pending.next"
    mv "$pending.next" "$pending"
    if grep -Fqx "$parent" "$visited"; then
      continue
    fi
    printf '%s\n' "$parent" >>"$visited"
    cursor=
    fetched=0
    while :; do
      if [ -n "$cursor" ]; then
        page=$(gh api graphql -F "owner=$owner" -F "name=$name" -F "number=$parent" \
          -f "after=$cursor" -F "query=@$references/clean-subissues.graphql" 2>&1) || {
          printf '%s: cannot read the sub-issues of #%s\n%s\n' "$command_name" "$parent" "$page" >&2
          exit 2
        }
      else
        page=$(gh api graphql -F "owner=$owner" -F "name=$name" -F "number=$parent" \
          -F "query=@$references/clean-subissues.graphql" 2>&1) || {
          printf '%s: cannot read the sub-issues of #%s\n%s\n' "$command_name" "$parent" "$page" >&2
          exit 2
        }
      fi
      printf '%s' "$page" | jq -e '.data.repository.issue.subIssues.nodes | type == "array"' >/dev/null 2>&1 || {
        echo "$command_name: cannot read the sub-issues of #$parent" >&2
        exit 2
      }
      foreign_issue=$(printf '%s' "$page" | jq -r --arg repository "$canonical_repository" '
        [.data.repository.issue.subIssues.nodes[] |
          select(.repository.nameWithOwner != $repository)] |
        first // empty | "\(.repository.nameWithOwner)#\(.number)"
      ')
      [ -z "$foreign_issue" ] || {
        echo "$command_name: cancel works in one repository, but #$parent has the sub-issue $foreign_issue" >&2
        exit 2
      }
      if [ "$root_recorded" = "false" ]; then
        printf '%s' "$page" | jq -c '.data.repository.issue | del(.subIssues)' >>"$tree_lines"
        root_recorded=true
      fi
      printf '%s' "$page" | jq -c '.data.repository.issue.subIssues.nodes[] | del(.subIssues)' >>"$tree_lines"
      printf '%s' "$page" | jq -r '
        .data.repository.issue.subIssues.nodes[] | select(.subIssues.totalCount > 0) | .number
      ' >>"$pending"
      fetched=$((fetched + $(printf '%s' "$page" | jq '.data.repository.issue.subIssues.nodes | length')))
      [ "$(printf '%s' "$page" | jq -r '.data.repository.issue.subIssues.pageInfo.hasNextPage')" = "true" ] || break
      cursor=$(printf '%s' "$page" | jq -r '.data.repository.issue.subIssues.pageInfo.endCursor // empty')
      [ -n "$cursor" ] || {
        echo "$command_name: GitHub returned no cursor for the next sub-issues of #$parent" >&2
        exit 2
      }
    done
    expected=$(printf '%s' "$page" | jq '.data.repository.issue.subIssues.totalCount')
    [ "$fetched" -eq "$expected" ] || {
      echo "$command_name: GitHub returned $fetched of $expected sub-issues of #$parent" >&2
      exit 2
    }
  done
  jq -s '.' "$tree_lines" >"$issues_file"
  jq -e 'all(.[]; .linkedBranches.totalCount <= (.linkedBranches.nodes | length))' \
    "$issues_file" >/dev/null || {
    echo "$command_name: GitHub truncated a linked branch list" >&2
    exit 2
  }

  issue_numbers=$temporary_directory/issue-numbers
  jq -r '.[].number' "$issues_file" >"$issue_numbers"
  numbers_pattern=$(paste -sd '|' "$issue_numbers")

  linked_branches=$temporary_directory/linked-branches
  jq -r --arg repository "$canonical_repository" '
    .[] | .linkedBranches.nodes[] |
    select(.ref.repository.nameWithOwner == $repository) |
    .ref.name
  ' "$issues_file" | sort -u >"$linked_branches"

  while IFS= read -r branch; do
    if grep -Fqx "$branch" "$linked_branches" ||
       printf '%s\n' "$branch" | grep -Eq "(^|[-_/])(${numbers_pattern})([-_/]|$)"; then
      printf '%s\n' "$branch" >>"$candidate_branches"
    fi
  done <"$all_branches"
else
  # Clean starts from the branches. Each issue number in a branch name is a
  # possible owner. GitHub returns the state and the parent chain of only
  # those issues, so the query size depends on the branches, not on the tree.
  branch_numbers=$temporary_directory/branch-numbers
  awk -F '[-_/]' '{
    for (i = 1; i <= NF; i++) {
      token = $i
      if (token ~ /^[1-9][0-9]*$/ && length(token) <= 9) print $0 "\t" token
    }
  }' "$all_branches" >"$branch_numbers"

  scope_numbers=$temporary_directory/scope-numbers
  {
    printf '%s\n' "$number"
    cut -f2 "$branch_numbers"
  } | sort -nu >"$scope_numbers"

  scope_lines=$temporary_directory/scope-lines
  : >"$scope_lines"
  scope_total=$(wc -l <"$scope_numbers" | tr -d ' ')
  scope_start=1
  while [ "$scope_start" -le "$scope_total" ]; do
    scope_end=$((scope_start + 49))
    scope_query=$({
      printf 'query($owner: String!, $name: String!) {\n  repository(owner: $owner, name: $name) {\n'
      sed -n "${scope_start},${scope_end}p" "$scope_numbers" |
        awk 'NF { printf "    i%s: issue(number: %s) {\n      ...CleanScopeIssue\n    }\n", $1, $1 }'
      printf '  }\n}\n\n'
      cat "$references/clean-scope.graphql"
    })
    # GitHub reports a number that is not an issue as a NOT_FOUND error and
    # still returns the other issues.
    scope_error=$temporary_directory/scope-error
    scope_json=$(gh api graphql -F "owner=$owner" -F "name=$name" -f "query=$scope_query" 2>"$scope_error") || true
    printf '%s' "$scope_json" | jq -e '
      (.data.repository | type) == "object" and
      all((.errors // [])[]; .type == "NOT_FOUND" and .path[0] == "repository" and (.path | length) == 2)
    ' >/dev/null 2>&1 || {
      echo "$command_name: cannot read the issues that the branch names reference" >&2
      cat "$scope_error" >&2
      exit 2
    }
    printf '%s' "$scope_json" | jq -c --arg repository "$canonical_repository" --argjson target "$number" '
      # A parent in another repository ends the chain, because its number
      # does not name an issue in this repository.
      def chain:
        if (.parent | type) == "object" and .parent.repository.nameWithOwner == $repository
        then [.parent.number] + (.parent | chain) else [] end;
      .data.repository[] | select(. != null) |
      chain as $chain |
      (.number == $target or ($chain | index($target)) != null) as $in_scope |
      {
        number,
        title,
        state,
        scope: (if $in_scope then "in" elif ($chain | length) >= 9 then "unknown" else "out" end),
        linked: [.linkedBranches.nodes[] | select(.ref.repository.nameWithOwner == $repository) | .ref.name],
        linkedTruncated: (.linkedBranches.totalCount > (.linkedBranches.nodes | length))
      }
    ' >>"$scope_lines"
    scope_start=$((scope_end + 1))
  done
  jq -s '.' "$scope_lines" >"$issues_file"
  jq -e --argjson target "$number" 'any(.[]; .number == $target)' "$issues_file" >/dev/null || {
    echo "$command_name: issue #$number was not found" >&2
    exit 2
  }
  jq -e 'all(.[]; .scope != "in" or (.linkedTruncated | not))' "$issues_file" >/dev/null || {
    echo "$command_name: GitHub truncated a linked branch list" >&2
    exit 2
  }

  # One row for each branch and each issue that can own it: the branch, the
  # issue number, the scope, and the issue state. Only rows in scope or of
  # unknown scope make a branch a candidate. Rows out of scope keep the open
  # state of other issues, so a branch of an open issue is never removed.
  # A link from an issue that is not in scope counts as out of scope.
  scope_table=$temporary_directory/scope-table
  jq -r '.[] | [(.number | tostring), .scope, .state] | @tsv' \
    "$issues_file" >"$scope_table"
  {
    awk -F '\t' 'NR == FNR { scope[$1] = $2 "\t" $3; next }
      ($2 in scope) { print $1 "\t" $2 "\t" scope[$2] }' "$scope_table" "$branch_numbers"
    jq -r '.[] | (.number | tostring) as $number | .state as $state |
      (if .scope == "in" then "in" else "out" end) as $scope |
      .linked[] | [., $number, $scope, $state] | @tsv' "$issues_file" |
      awk -F '\t' 'NR == FNR { keep[$0] = 1; next } ($1 in keep)' "$all_branches" -
  } | sort -u >"$branch_issues"
  awk -F '\t' '$3 != "out" { print $1 }' "$branch_issues" | sort -u >"$candidate_branches"
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
    if [ "$worktree_path" = "$current_checkout" ]; then
      reason="branch is active in the current checkout"
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
      reason="worktree is locked: $worktree_path"
    fi
  fi

  if [ -z "$reason" ] && [ "$operation" = "clean" ]; then
    open_issue=$(awk -F '\t' -v branch="$branch" \
      '$1 == branch && $4 == "OPEN" { print $2; exit }' "$branch_issues")
    unknown_issue=$(awk -F '\t' -v branch="$branch" '
      $1 == branch && $3 == "in" { in_scope = 1 }
      $1 == branch && $3 == "unknown" && unknown == "" { unknown = $2 }
      END { if (!in_scope) print unknown }
    ' "$branch_issues")
    if [ -n "$open_issue" ]; then
      reason="issue #$open_issue is open"
    elif [ -n "$unknown_issue" ]; then
      reason="cannot confirm that issue #$unknown_issue is under #$number"
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
preserved_count=$(wc -l <"$preserved" | tr -d ' ')
warning_count=$(wc -l <"$warnings" | tr -d ' ')
action_count=$((worktree_count + local_count + remote_count + issue_count + pr_count))

render_detailed_plan() {
  if [ "$operation" = "cancel" ]; then
    printf 'Cancel plan: issue #%s resolves to #%s %s\n' "$number" "$root_number" "$root_title"
    printf 'Issues to close as Not planned: %s\n' "$issue_count"
    awk -F '\t' '{ printf "- #%s %s\n", $1, $2 }' "$close_issues"
    printf 'Pull requests to close: %s\n' "$pr_count"
    awk -F '\t' '{ printf "- #%s %s [%s]\n", $1, $2, $3 }' "$close_prs"
  else
    printf 'Clean plan: issue #%s %s, with its sub-issues\n' "$number" "$root_title"
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
  printf 'Preserved: %s\n' "$preserved_count"
  awk -F '\t' '{ printf "- %s: %s\n", $1, $2 }' "$preserved"
  printf 'Warnings: %s\n' "$warning_count"
  awk -F '\t' '{ printf "- %s: %s\n", $1, $2 }' "$warnings"
}

if [ "$action_count" -eq 0 ]; then
  plan_output=$({
    render_detailed_plan
    if [ "$operation" = "cancel" ]; then
      printf 'Nothing is eligible for cancellation.\n'
    else
      printf 'Nothing is eligible for cleanup.\n'
    fi
  })
  printf '%s\n' "$plan_output"
  exit 0
fi

plan_token=$({
  printf 'operation\t%s\nrepository\t%s\nscope\t%s\nstable\t%s\t%s\nlocal-only\t%s\n' \
    "$operation" "$canonical_repository" "$root_number" "$stable_branch" "$stable_oid" "$local_only"
  sed 's/^/issue\t/' "$close_issues"
  sed 's/^/pr\t/' "$close_prs"
  sed 's/^/worktree\t/' "$remove_worktrees"
  sed 's/^/local\t/' "$remove_local"
  sed 's/^/remote\t/' "$remove_remote"
  sed 's/^/preserved\t/' "$preserved"
  sed 's/^/warning\t/' "$warnings"
} | hash_plan)

if [ -z "$confirmation" ]; then
  plan_output=$({
    render_detailed_plan
    printf 'Confirmation token: %s\n' "$plan_token"
    printf 'No changes were made. Confirm this exact plan before applying it.\n'
  })
  printf '%s\n' "$plan_output"
  exit 0
fi

[ "$confirmation" = "$plan_token" ] || {
  plan_output=$({
    render_detailed_plan
    printf 'Confirmation token: %s\n' "$plan_token"
    printf 'No changes were made. Confirm this exact plan before applying it.\n'
  })
  printf '%s\n' "$plan_output"
  echo "$command_name: the confirmation token does not match the current plan; review the new plan" >&2
  exit 2
}

confirmation_summary=$({
  if [ "$operation" = "cancel" ]; then
    printf 'Confirmed cancellation plan summary\n'
    printf 'Issues to close as Not planned: %s\n' "$issue_count"
    printf 'Pull requests to close: %s\n' "$pr_count"
  else
    printf 'Confirmed cleanup plan summary\n'
  fi
  printf 'Repository: %s\n' "$canonical_repository"
  printf 'Mode: %s\n' "$([ "$local_only" = "true" ] && printf 'local only' || printf 'local and remote')"
  printf 'Worktrees to remove: %s\n' "$worktree_count"
  printf 'Local branches to remove: %s\n' "$local_count"
  printf 'Remote branches to remove: %s\n' "$remote_count"
  printf 'Preserved: %s\n' "$preserved_count"
  printf 'Warnings: %s\n' "$warning_count"
})
printf '%s\n' "$confirmation_summary"

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
  if [ "$operation" = "cancel" ]; then
    git worktree remove --force --force "$worktree_path"
  else
    git worktree remove "$worktree_path"
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
