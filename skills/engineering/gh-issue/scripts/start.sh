#!/bin/sh
set -eu

usage() {
  echo "usage: start.sh start|resume [--branch BRANCH] [--base BRANCH] [--destination PATH] [--manager auto|supacode|git] [--accept-in-use PATH] [--project-override JSON] OWNER/REPOSITORY|. ISSUE_NUMBER" >&2
  exit 64
}

needs_input() {
  field=$1
  question=$2
  candidates_file=${3:-}
  if [ -n "$candidates_file" ] && [ -s "$candidates_file" ]; then
    candidates=$(jq -Rsc 'split("\n") | map(select(length > 0))' "$candidates_file")
  else
    candidates='[]'
  fi
  jq -cn --arg field "$field" --arg question "$question" --argjson candidates "$candidates" \
    '{status:"needs_input", field:$field, question:$question, candidates:$candidates}'
  exit 2
}

slugify() {
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//' |
    cut -c1-48 |
    sed 's/-$//'
}

render_template() {
  printf '%s' "$1" | sed "s/{number}/$2/g; s/{slug}/$3/g"
}

branch_matches_issue() {
  printf '%s\n' "$1" | awk -v number="$2" '
    $0 ~ "(^|[-_/])" number "([-_/]|$)" { found = 1 }
    END { exit !found }
  '
}

collect_candidates() {
  issue_number=$1
  output=$2
  : >"$output"

  jq -r --argjson number "$issue_number" --arg repository "$canonical_repository" '
    .[] | select(.number == $number) |
    .linkedBranches.nodes[]? |
    select((.ref.repository.nameWithOwner | ascii_downcase) == ($repository | ascii_downcase)) |
    .ref.name
  ' "$hierarchy_file" >>"$output"

  git -C "$primary" for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin |
    sed 's#^origin/##' |
    while IFS= read -r candidate; do
      if branch_matches_issue "$candidate" "$issue_number"; then
        printf '%s\n' "$candidate"
      fi
    done >>"$output"

  awk -F '\t' -v number="$issue_number" '
    $2 ~ "(^|[-_/])" number "([-_/]|$)" { print $2 }
  ' "$worktree_rows" >>"$output"

  sort -u "$output" -o "$output"
}

worktree_for_branch() {
  awk -F '\t' -v branch="$1" '$2 == branch { print $1 }' "$worktree_rows"
}

branch_exists_locally() {
  git -C "$primary" show-ref --verify --quiet "refs/heads/$1"
}

branch_exists_remotely() {
  git -C "$primary" show-ref --verify --quiet "refs/remotes/origin/$1"
}

branch_reference() {
  if branch_exists_remotely "$1"; then
    printf 'refs/remotes/origin/%s\n' "$1"
  elif branch_exists_locally "$1"; then
    printf 'refs/heads/%s\n' "$1"
  else
    echo "start.sh: base branch $1 is unavailable" >&2
    return 2
  fi
}

assign_issue() {
  assignee_count=$(jq -r '.data.repository.issue.assignees.totalCount' "$issue_json")
  assignee_loaded=$(jq -r '.data.repository.issue.assignees.nodes | length' "$issue_json")
  [ "$assignee_count" = "$assignee_loaded" ] || {
    echo "start.sh: GitHub truncated issue assignees" >&2
    return 2
  }
  if [ "$assignee_count" -eq 0 ]; then
    assignee=$(gh api user --jq '.login')
    [ -n "$assignee" ] || return 2
    gh issue edit "$number" --repo "$canonical_repository" --add-assignee "$assignee" >/dev/null
    assignment="$assignee (assigned)"
  else
    assignment="$(jq -r '.data.repository.issue.assignees.nodes | map(.login) | join(", ")' "$issue_json") (preserved)"
  fi
}

[ "$#" -ge 1 ] || usage
mode=$1
shift
case "$mode" in
  start|resume) ;;
  *) usage ;;
esac

selected_branch=
selected_base=
selected_destination=
selected_manager=
accepted_in_use=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch|--base|--destination|--manager|--accept-in-use|--project-override)
      [ "$#" -ge 2 ] || usage
      case "$1" in
        --branch) selected_branch=$2 ;;
        --base) selected_base=$2 ;;
        --destination) selected_destination=$2 ;;
        --manager) selected_manager=$2 ;;
        --accept-in-use) accepted_in_use=$2 ;;
        --project-override) AGENT_SKILLS_PROJECT_OVERRIDE=$2; export AGENT_SKILLS_PROJECT_OVERRIDE ;;
      esac
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
case "$selected_manager" in
  ''|auto|supacode|git) ;;
  *) usage ;;
esac

command -v jq >/dev/null 2>&1 || {
  echo "start.sh: jq is required" >&2
  exit 69
}
command -v git >/dev/null 2>&1 || {
  echo "start.sh: git is required" >&2
  exit 69
}

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-start.XXXXXX")
trap 'find "$temporary_directory" -type f -delete 2>/dev/null || true; rmdir "$temporary_directory" 2>/dev/null || true' EXIT HUP INT TERM

issue_json=$temporary_directory/issue.json
if ! "$script_directory/query.sh" start "$repository" "$number" >"$issue_json"; then
  echo "start.sh: cannot read issue #$number" >&2
  exit 2
fi

issue_exists=$(jq -r '.data.repository.issue != null' "$issue_json")
[ "$issue_exists" = "true" ] || {
  echo "start.sh: issue #$number was not found" >&2
  exit 2
}

canonical_repository=$(jq -er '.data.repository.nameWithOwner' "$issue_json")
default_branch=$(jq -er '.data.repository.defaultBranchRef.name' "$issue_json")
focused_state=$(jq -r '.data.repository.issue.state' "$issue_json")
[ "$focused_state" = "OPEN" ] || {
  echo "start.sh: issue #$number is $focused_state" >&2
  exit 2
}

hierarchy_file=$temporary_directory/hierarchy.json
if ! jq -ce '
  def hierarchy:
    [.] + (if (.parent? | type) == "object" then (.parent | hierarchy) else [] end);
  (.data.repository.issue | hierarchy) as $hierarchy |
  if any($hierarchy[]; .state != "OPEN") then
    error("the issue hierarchy contains a closed issue")
  elif any($hierarchy[]; .linkedBranches.totalCount > (.linkedBranches.nodes | length)) then
    error("GitHub truncated linked branches")
  elif ($hierarchy[-1].parent? | type) == "object" then
    error("GitHub truncated the ancestor hierarchy")
  else $hierarchy end
' "$issue_json" >"$hierarchy_file"; then
  echo "start.sh: issue hierarchy is closed or incomplete" >&2
  exit 2
fi

current_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "start.sh: run this command from a checkout of $canonical_repository" >&2
  exit 69
}
git -C "$current_root" worktree list --porcelain >"$temporary_directory/worktrees"
primary=$(awk '/^worktree / { print substr($0, 10); exit }' "$temporary_directory/worktrees")
[ -n "$primary" ] || {
  echo "start.sh: cannot resolve the primary checkout" >&2
  exit 69
}

local_repository=$(git -C "$primary" config --get remote.origin.url 2>/dev/null || true)
case "$local_repository" in
  git@github.com:*) local_repository=${local_repository#git@github.com:} ;;
  https://github.com/*) local_repository=${local_repository#https://github.com/} ;;
  ssh://git@github.com/*) local_repository=${local_repository#ssh://git@github.com/} ;;
  *) local_repository= ;;
esac
local_repository=${local_repository%.git}
if [ -z "$local_repository" ] || [ "$(printf '%s' "$local_repository" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$canonical_repository" | tr '[:upper:]' '[:lower:]')" ]; then
  echo "start.sh: current checkout is not $canonical_repository" >&2
  exit 69
fi

worktree_rows=$temporary_directory/worktree-rows
awk '
  function emit() {
    if (path != "" && branch != "") print path "\t" branch
  }
  /^worktree / { emit(); path = substr($0, 10); branch = ""; next }
  /^branch refs\/heads\// { branch = substr($0, 19); next }
  END { emit() }
' "$temporary_directory/worktrees" >"$worktree_rows"

config=$("$script_directory/start-config.sh" "$canonical_repository")
configured_base=$(printf '%s' "$config" | jq -r '.taskBaseBranch // empty')
if [ -z "$selected_base" ] && [ "$(jq -r '.[0].subIssues.totalCount // 0' "$hierarchy_file")" -eq 0 ]; then
  selected_base=$configured_base
fi
if [ -n "$selected_base" ]; then
  git check-ref-format "refs/heads/$selected_base" >/dev/null || {
    echo "start.sh: invalid base branch $selected_base" >&2
    exit 2
  }
fi
configured_manager=$(printf '%s' "$config" | jq -r '.worktreeManager')
[ -z "$selected_manager" ] || configured_manager=$selected_manager

focused_candidates=$temporary_directory/focused-candidates
collect_candidates "$number" "$focused_candidates"
focused_candidate_count=$(wc -l <"$focused_candidates" | tr -d ' ')
if [ -n "$selected_branch" ]; then
  if [ "$focused_candidate_count" -gt 0 ] && ! grep -Fx "$selected_branch" "$focused_candidates" >/dev/null; then
    needs_input branch "Which existing branch should issue #$number use?" "$focused_candidates"
  fi
  focused_branch=$selected_branch
elif [ "$focused_candidate_count" -eq 1 ]; then
  focused_branch=$(sed -n '1p' "$focused_candidates")
elif [ "$focused_candidate_count" -gt 1 ]; then
  needs_input branch "Which existing branch should issue #$number use?" "$focused_candidates"
else
  focused_branch=
fi

existing_worktree=
if [ -n "$focused_branch" ]; then
  existing_worktree=$(worktree_for_branch "$focused_branch")
  existing_worktree_count=$(printf '%s\n' "$existing_worktree" | awk 'NF { count++ } END { print count + 0 }')
  if [ "$existing_worktree_count" -gt 1 ]; then
    printf '%s\n' "$existing_worktree" >"$temporary_directory/conflicting-worktrees"
    if [ -n "$selected_destination" ] && grep -Fx "$selected_destination" "$temporary_directory/conflicting-worktrees" >/dev/null; then
      existing_worktree=$selected_destination
    else
      needs_input destination "Which worktree should issue #$number use?" "$temporary_directory/conflicting-worktrees"
    fi
  fi
fi

issue_title=$(jq -r '.[0].title' "$hierarchy_file")
issue_slug=$(slugify "$issue_title")
[ -n "$issue_slug" ] || issue_slug=work
repository_name=${canonical_repository#*/}
configured_root=$(printf '%s' "$config" | jq -r '.worktreeRoot // empty')
if [ -z "$configured_root" ]; then
  checkout_container=$(dirname -- "$primary")
  configured_root="$(dirname -- "$checkout_container")/worktrees"
fi
repository_worktree_root=${configured_root%/}/$repository_name
worktree_template=$(printf '%s' "$config" | jq -r '.worktreeTemplate')
worktree_name=$(render_template "$worktree_template" "$number" "$issue_slug")
destination=${selected_destination:-${repository_worktree_root%/}/$worktree_name}
worktree_location=$(dirname -- "$destination")
worktree_name=$(basename -- "$destination")

if [ -z "$existing_worktree" ] && [ -e "$destination" ]; then
  printf '%s\n' "$destination" >"$temporary_directory/destination"
  needs_input destination "Which unused destination should issue #$number use?" "$temporary_directory/destination"
fi

supacode_repository_id=
if [ "$configured_manager" != "git" ] && command -v supacode >/dev/null 2>&1; then
  expected_id=$(jq -nr --arg value "${primary%/}/" '$value | @uri')
  if supacode repo list --timeout 5 >"$temporary_directory/supacode-repositories" 2>/dev/null; then
    supacode_repository_id=$(grep -Fx "$expected_id" "$temporary_directory/supacode-repositories" || true)
  fi
fi

case "$configured_manager" in
  git) manager=git ;;
  auto)
    if [ -n "$supacode_repository_id" ]; then manager=supacode; else manager=git; fi
    ;;
  supacode)
    if [ -z "$supacode_repository_id" ]; then
      printf '%s\n' git >"$temporary_directory/managers"
      needs_input manager "Supacode does not contain $canonical_repository. Which worktree manager should be used?" "$temporary_directory/managers"
    fi
    manager=supacode
    ;;
esac

project_output=$temporary_directory/project-output
if ! "$script_directory/project-start.sh" --dry-run "$canonical_repository" "$number" >"$project_output"; then
  cat "$project_output"
  exit 2
fi

render_projects() {
  jq -r '
    "Project status synchronization: " + .status,
    (.updates[] | "Project " + .board + " issue #" + (.issue | tostring) + ": " + .field + " → " + .expected + " [" + .status + "]")
  ' "$project_output"
}

apply_projects() {
  if ! "$script_directory/project-start.sh" "$canonical_repository" "$number" >"$project_output"; then
    cat "$project_output"
    exit 2
  fi
}

hierarchy_text=$(jq -r 'reverse | map("#" + (.number | tostring) + " " + .title) | join(" > ")' "$hierarchy_file")
if [ -n "$existing_worktree" ]; then
  if [ "$(git -C "$existing_worktree" branch --show-current 2>/dev/null || true)" != "$focused_branch" ]; then
    echo "start.sh: existing worktree verification failed for $existing_worktree" >&2
    exit 2
  fi
  # Another session can work in the same worktree. Ask before attaching it.
  if ! evidence=$("$script_directory/worktree-evidence.sh" "$existing_worktree" "$focused_branch"); then
    echo "start.sh: worktree evidence failed for $existing_worktree" >&2
    exit 2
  fi
  if printf '%s' "$evidence" | jq -e '(.supacodeTabs // 0) > 0 or .uncommitted > 0' >/dev/null &&
    [ "${accepted_in_use%/}" != "${existing_worktree%/}" ]; then
    printf '%s\n' "$existing_worktree" >"$temporary_directory/in-use"
    needs_input accept-in-use "Worktree $existing_worktree for issue #$number looks in use: $(printf '%s' "$evidence" | jq -r '.summary'). Another session can work in it. Attach it anyway?" "$temporary_directory/in-use"
  fi
  apply_projects
  assign_issue
  printf 'Assignees: %s\n' "$assignment"
  printf 'Status: existing_worktree\n'
  printf 'Repository: %s\n' "$canonical_repository"
  printf 'Issue: #%s %s\n' "$number" "$issue_title"
  printf 'Hierarchy: %s\n' "$hierarchy_text"
  printf 'Branch: %s\n' "$focused_branch"
  printf 'Worktree: %s\n' "$existing_worktree"
  render_projects
  exit 0
fi

if [ -n "$focused_branch" ] && [ "$mode" = "start" ]; then
  assign_issue
  printf 'Assignees: %s\n' "$assignment"
  printf 'Status: already_started\n'
  printf 'Repository: %s\n' "$canonical_repository"
  printf 'Issue: #%s %s\n' "$number" "$issue_title"
  printf 'Hierarchy: %s\n' "$hierarchy_text"
  printf 'Branch: %s\n' "$focused_branch"
  printf 'Worktree: none\n'
  render_projects
  printf 'Next: resume issue #%s to attach its existing branch.\n' "$number"
  exit 0
fi

creation_plan=$temporary_directory/creation-plan
: >"$creation_plan"
if [ -z "$focused_branch" ]; then
  git -C "$primary" fetch origin
  previous_branch=${selected_base:-$default_branch}
  previous_ref=$(branch_reference "$previous_branch")
  comparison_branch=$previous_branch
  if [ -z "$selected_base" ]; then
    jq -c 'reverse[]' "$hierarchy_file" >"$temporary_directory/hierarchy-lines"
  else
    jq -c '.[0]' "$hierarchy_file" >"$temporary_directory/hierarchy-lines"
  fi

  while IFS= read -r issue; do
    item_number=$(printf '%s' "$issue" | jq -r '.number')
    item_title=$(printf '%s' "$issue" | jq -r '.title')
    item_slug=$(slugify "$item_title")
    [ -n "$item_slug" ] || item_slug=work
    item_candidates=$temporary_directory/candidates-$item_number
    collect_candidates "$item_number" "$item_candidates"
    item_candidate_count=$(wc -l <"$item_candidates" | tr -d ' ')

    if [ "$item_number" -eq "$number" ] && [ -n "$selected_branch" ]; then
      item_branch=$selected_branch
    elif [ "$item_candidate_count" -eq 1 ]; then
      item_branch=$(sed -n '1p' "$item_candidates")
    elif [ "$item_candidate_count" -gt 1 ]; then
      needs_input base "Which existing branch should provide the base for issue #$number?" "$item_candidates"
    else
      if [ "$item_number" -eq "$number" ]; then
        child_count=$(printf '%s' "$issue" | jq -r '.subIssues.totalCount // 0')
        if [ "$child_count" -gt 0 ]; then
          template=$(printf '%s' "$config" | jq -r '.integrationBranchTemplate')
        else
          template=$(printf '%s' "$config" | jq -r '.taskBranchTemplate')
        fi
      else
        template=$(printf '%s' "$config" | jq -r '.integrationBranchTemplate')
      fi
      item_branch=$(render_template "$template" "$item_number" "$item_slug")
      printf '%s\t%s\t%s\n' "$item_number" "$item_branch" "$previous_branch" >>"$creation_plan"
    fi
    if [ "$item_candidate_count" -eq 1 ] && [ "$item_number" -ne "$number" ]; then
      item_ref=$(branch_reference "$item_branch")
      missing=$(git -C "$primary" rev-list --count "$item_ref..$previous_ref")
      if [ "$missing" -gt 0 ]; then
        printf '%s\n%s\n' "$comparison_branch" "$item_branch" >"$temporary_directory/stale-bases"
        needs_input base "Ancestor branch $item_branch is missing $missing commit(s) from $comparison_branch. Which base should issue #$number use?" "$temporary_directory/stale-bases"
      fi
      previous_ref=$item_ref
      comparison_branch=$item_branch
    fi
    previous_branch=$item_branch
    if [ "$item_number" -eq "$number" ]; then focused_branch=$item_branch; fi
  done <"$temporary_directory/hierarchy-lines"
fi

while IFS="$(printf '\t')" read -r item_number item_branch item_base; do
  [ -n "$item_number" ] || continue
  gh issue develop "$item_number" --repo "$canonical_repository" --base "$item_base" --name "$item_branch" >/dev/null
done <"$creation_plan"

if [ -s "$creation_plan" ] || ! branch_exists_locally "$focused_branch"; then
  git -C "$primary" fetch origin
fi

if branch_exists_locally "$focused_branch"; then
  attach_kind=local
elif branch_exists_remotely "$focused_branch"; then
  attach_kind=remote
else
  echo "start.sh: branch $focused_branch is unavailable after creation" >&2
  exit 2
fi

mkdir -p "$worktree_location"
if [ "$manager" = "supacode" ]; then
  if [ "$attach_kind" = "local" ]; then
    worktree_id=$(supacode repo worktree-new -r "$supacode_repository_id" --branch "$focused_branch" --location "$worktree_location" --name "$worktree_name" --background)
  else
    worktree_id=$(supacode repo worktree-new -r "$supacode_repository_id" --branch "$focused_branch" --base "origin/$focused_branch" --upstream "origin/$focused_branch" --location "$worktree_location" --name "$worktree_name" --background)
  fi
else
  if [ "$attach_kind" = "local" ]; then
    git -C "$primary" worktree add "$destination" "$focused_branch" >/dev/null
  else
    git -C "$primary" worktree add -b "$focused_branch" --track "$destination" "origin/$focused_branch" >/dev/null
  fi
  worktree_id=
fi

checked_out_branch=$(git -C "$destination" branch --show-current 2>/dev/null || true)
[ "$checked_out_branch" = "$focused_branch" ] || {
  echo "start.sh: worktree verification failed for $destination" >&2
  exit 2
}

assign_issue
apply_projects
if [ "$mode" = "resume" ]; then result=resumed; else result=started; fi
printf 'Status: %s\n' "$result"
printf 'Repository: %s\n' "$canonical_repository"
printf 'Issue: #%s %s\n' "$number" "$issue_title"
printf 'Hierarchy: %s\n' "$hierarchy_text"
printf 'Branch: %s\n' "$focused_branch"
printf 'Worktree: %s\n' "$destination"
printf 'Assignees: %s\n' "$assignment"
printf 'Manager: %s\n' "$manager"
[ -z "$worktree_id" ] || printf 'Supacode worktree ID: %s\n' "$worktree_id"
render_projects
